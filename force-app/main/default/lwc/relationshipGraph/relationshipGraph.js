import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import D3 from '@salesforce/resourceUrl/d3';
import getGraphData from '@salesforce/apex/RelationshipGraphController.getGraphData';
import refreshGraphData from '@salesforce/apex/RelationshipGraphController.refreshGraphData';
import getGraphConfig from '@salesforce/apex/RelationshipGraphController.getGraphConfig';
import overrideClassification from '@salesforce/apex/RelationshipGraphController.overrideClassification';

// Classification color map
const CLASSIFICATION_COLORS = {
    'Champion': '#2e7d32',       // Green
    'Economic Buyer': '#1565c0', // Blue
    'Technical Buyer': '#6a1b9a',// Purple
    'Blocker': '#c62828',        // Red
    'Influencer': '#ef6c00',     // Orange
    'End User': '#78909c',       // Grey-blue
    'Detractor': '#b71c1c',      // Dark red
    'Unknown': '#9e9e9e'         // Grey
};

const NODE_TYPE_SHAPES = {
    'Account': 'diamond',
    'Contact': 'circle',
    'Opportunity': 'square',
    'External_Contact': 'hexagon',
    'Moved_To_Company': 'diamond'
};

const NODE_TYPE_COLORS = {
    'Account': '#0176d3',
    'Opportunity': '#ff9800',
    'External_Contact': '#00897b'
};

export default class RelationshipGraph extends NavigationMixin(LightningElement) {
    @api recordId; // Account ID from record page
    @api showAllContacts = false;
    @api defaultMinInteractions = 3;

    graphData = null;
    selectedNode = null;
    isLoading = true;
    hidePassive = true;
    minInteractions = 3;
    activeFilters = [];
    config = {};
    hiddenCount = 0;
    isTruncated = false;
    totalContactCount = 0;
    riskAlerts = [];
    showRiskPanel = false;
    showExternalContacts = false;
    externalContactCount = 0;
    showHierarchy = false;
    hierarchyAccountCount = 0;
    movedContactCount = 0;
    riskNodeIds = new Map(); // nodeId → highest severity
    clusters = new Map(); // clusterId → { nodes, label, color }
    _accountName = '';

    d3Initialized = false;
    simulation = null;
    canvas = null;
    ctx = null;
    transform = { x: 0, y: 0, k: 1 };
    nodes = [];
    edges = [];
    hoveredNode = null;
    draggedNode = null;
    width = 0;
    height = 0;
    animationFrame = null;

    // ─── Lifecycle ──────────────────────────────────────────────────

    get _storageKey() {
        return 'relgraph_' + (this.recordId || '');
    }

    _saveToggleState() {
        try {
            sessionStorage.setItem(this._storageKey, JSON.stringify({
                hidePassive: this.hidePassive,
                showExternalContacts: this.showExternalContacts,
                showHierarchy: this.showHierarchy,
                minInteractions: this.minInteractions
            }));
        } catch (e) { /* sessionStorage may be unavailable */ }
    }

    _restoreToggleState() {
        try {
            const saved = sessionStorage.getItem(this._storageKey);
            if (saved) {
                const s = JSON.parse(saved);
                this.hidePassive = s.hidePassive;
                this.showExternalContacts = s.showExternalContacts;
                this.showHierarchy = s.showHierarchy;
                this.minInteractions = s.minInteractions;
                return true;
            }
        } catch (e) { /* ignore */ }
        return false;
    }

    connectedCallback() {
        if (!this._restoreToggleState()) {
            this.hidePassive = !this.showAllContacts;
            this.minInteractions = this.defaultMinInteractions;
        }
        this.loadConfig();
    }

    renderedCallback() {
        if (this.d3Initialized) return;
        this.d3Initialized = true;

        loadScript(this, D3)
            .then(() => {
                this.initCanvas();
                this.loadGraphData();
            })
            .catch(error => {
                this.showError('Failed to load D3.js: ' + error.message);
            });
    }

    disconnectedCallback() {
        if (this.animationFrame) {
            cancelAnimationFrame(this.animationFrame);
        }
        if (this.simulation) {
            this.simulation.stop();
        }
    }

    // ─── Data Loading ───────────────────────────────────────────────

    async loadConfig() {
        try {
            this.config = await getGraphConfig();
            if (this.config.minInteractions) {
                this.minInteractions = this.config.minInteractions;
            }
        } catch (error) {
            console.warn('Failed to load config, using defaults:', error);
        }
    }

    async loadGraphData() {
        this.isLoading = true;
        try {
            const data = await getGraphData({
                accountId: this.recordId,
                hidePassive: this.hidePassive,
                minInteractions: this.minInteractions,
                thresholdDays: this.config.activityThresholdDays || 90,
                showExternalContacts: this.showExternalContacts,
                showHierarchy: this.showHierarchy
            });
            this.processGraphData(data);
        } catch (error) {
            this.showError('Failed to load graph data: ' + this.extractErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    processGraphData(data) {
        if (!data || !data.nodes) {
            this.graphData = { nodes: [], edges: [] };
            return;
        }

        this.graphData = data;
        this.isTruncated = data.isTruncated || false;
        this.totalContactCount = data.totalContactCount || 0;
        this.externalContactCount = (data.nodes || []).filter(
            n => n.nodeType === 'External_Contact'
        ).length;
        this.hierarchyAccountCount = (data.nodes || []).filter(
            n => n.isHierarchyAccount === true
        ).length;
        this.movedContactCount = (data.nodes || []).filter(
            n => n.hasMovedCompany === true
        ).length;

        // Show FLS warnings if any
        if (data.warnings && data.warnings.length > 0) {
            this.showToast('Info', data.warnings.join('; '), 'info');
        }

        // Extract risk alerts
        this.riskAlerts = (data.riskAlerts || []).map((alert, idx) => ({
            ...alert,
            key: 'risk-' + idx,
            severityClass: 'risk-alert-item risk-severity-' + alert.severity,
            severityIcon: alert.severity === 'high' ? '\u26A0' : '\u26AB',
            isClickable: !!alert.contactId
        }));

        // Build risk node lookup
        this.riskNodeIds = new Map();
        for (const alert of this.riskAlerts) {
            if (alert.contactId) {
                const existing = this.riskNodeIds.get(alert.contactId);
                if (!existing || alert.severity === 'high') {
                    this.riskNodeIds.set(alert.contactId, alert.severity);
                }
            }
        }

        if (this.isTruncated) {
            this.showToast(
                'Large Account',
                `Showing 500 of ${this.totalContactCount}+ contacts. Use filters to focus.`,
                'warning'
            );
        }

        // Filter out primary Account node (keep hierarchy accounts)
        // Store account name for cluster labeling
        this._accountName = '';
        const filteredNodes = [];
        for (const n of data.nodes) {
            if (n.nodeType === 'Account' && !n.isHierarchyAccount) {
                this._accountName = n.name;
                // Keep account node only when hierarchy is active (needed as anchor)
                if (!this.showHierarchy) continue;
            }
            filteredNodes.push(n);
        }

        // Convert to D3-compatible format
        this.nodes = filteredNodes.map(n => ({
            ...n,
            x: this.width / 2 + (Math.random() - 0.5) * 300,
            y: this.height / 2 + (Math.random() - 0.5) * 300,
            radius: this.getNodeRadius(n),
            color: this.getNodeColor(n)
        }));

        // Build node ID map for edge resolution
        const nodeMap = new Map();
        this.nodes.forEach(n => nodeMap.set(n.id, n));

        // Filter out account_relationship edges (unless hierarchy mode)
        this.edges = data.edges
            .filter(e => {
                if (e.edgeType === 'account_relationship' && !this.showHierarchy) return false;
                return nodeMap.has(e.source) && nodeMap.has(e.target);
            })
            .map(e => ({
                ...e,
                source: nodeMap.get(e.source),
                target: nodeMap.get(e.target)
            }));

        // Add synthetic "moved to company" nodes for moved contacts
        let movedIdx = 0;
        for (const node of [...this.nodes]) {
            if (node.hasMovedCompany === true && node.previousCompany) {
                const realId = node.previousCompanyId || ('moved_to_' + movedIdx++);
                const movedToNode = {
                    id: realId,
                    name: node.previousCompany,
                    nodeType: 'Moved_To_Company',
                    recordId: node.previousCompanyId || null,
                    x: node.x + 120,
                    y: node.y - 60,
                    radius: this.getNodeRadius({ nodeType: 'Moved_To_Company' }),
                    color: this.getNodeColor({ nodeType: 'Moved_To_Company' })
                };
                this.nodes.push(movedToNode);
                this.edges.push({
                    source: node,
                    target: movedToNode,
                    edgeType: 'moved_to',
                    strength: 0.5,
                    interactionCount: 0
                });
            }
        }

        // Compute clusters from co-occurrence edges
        this.computeClusters();

        this.startSimulation();
    }

    // ─── Clustering ────────────────────────────────────────────────

    computeClusters() {
        const CLUSTER_HULL_COLORS = [
            'rgba(33, 150, 243, 0.08)',
            'rgba(76, 175, 80, 0.08)',
            'rgba(255, 152, 0, 0.08)',
            'rgba(156, 39, 176, 0.08)',
            'rgba(0, 150, 136, 0.08)',
            'rgba(244, 67, 54, 0.08)',
            'rgba(121, 85, 72, 0.08)',
            'rgba(63, 81, 181, 0.08)'
        ];

        // Build adjacency list from co-occurrence edges
        const adj = new Map();
        for (const edge of this.edges) {
            if (edge.edgeType !== 'co_occurrence') continue;
            const sId = typeof edge.source === 'object' ? edge.source.id : edge.source;
            const tId = typeof edge.target === 'object' ? edge.target.id : edge.target;
            const weight = edge.interactionCount || 1;

            if (!adj.has(sId)) adj.set(sId, []);
            if (!adj.has(tId)) adj.set(tId, []);
            adj.get(sId).push({ id: tId, weight });
            adj.get(tId).push({ id: sId, weight });
        }

        // Initialize: each contact gets its own label
        const labels = new Map();
        const contactNodes = this.nodes.filter(n => n.nodeType === 'Contact');
        contactNodes.forEach((n, i) => labels.set(n.id, i));

        // Weighted label propagation (max 10 passes)
        for (let iter = 0; iter < 10; iter++) {
            let changed = false;
            const shuffled = [...contactNodes].sort(() => Math.random() - 0.5);

            for (const node of shuffled) {
                const neighbors = adj.get(node.id);
                if (!neighbors || neighbors.length === 0) continue;

                const freq = new Map();
                for (const { id, weight } of neighbors) {
                    const label = labels.get(id);
                    if (label === undefined) continue;
                    freq.set(label, (freq.get(label) || 0) + weight);
                }
                if (freq.size === 0) continue;

                let bestLabel = labels.get(node.id);
                let bestWeight = 0;
                for (const [label, w] of freq) {
                    if (w > bestWeight) {
                        bestWeight = w;
                        bestLabel = label;
                    }
                }
                if (bestLabel !== labels.get(node.id)) {
                    labels.set(node.id, bestLabel);
                    changed = true;
                }
            }
            if (!changed) break;
        }

        // Normalize cluster IDs
        const uniqueLabels = [...new Set(labels.values())];
        const labelMap = new Map();
        uniqueLabels.forEach((label, idx) => labelMap.set(label, idx));

        // Assign to nodes
        for (const node of this.nodes) {
            if (node.nodeType === 'Contact') {
                node.clusterId = labelMap.get(labels.get(node.id));
            } else {
                node.clusterId = -1;
            }
        }

        // Build cluster metadata
        this.clusters = new Map();
        for (const node of this.nodes) {
            if (node.clusterId == null || node.clusterId < 0) continue;
            if (!this.clusters.has(node.clusterId)) {
                this.clusters.set(node.clusterId, { nodes: [] });
            }
            this.clusters.get(node.clusterId).nodes.push(node);
        }

        // Assign colors and labels
        for (const [clusterId, cluster] of this.clusters) {
            cluster.color = CLUSTER_HULL_COLORS[clusterId % CLUSTER_HULL_COLORS.length];
            const classFreq = {};
            for (const node of cluster.nodes) {
                const cls = node.classification || 'Unknown';
                classFreq[cls] = (classFreq[cls] || 0) + 1;
            }
            const sorted = Object.entries(classFreq).sort((a, b) => b[1] - a[1]);
            cluster.label = sorted[0][0] + ' group (' + cluster.nodes.length + ')';
        }

        // Largest cluster gets the account name
        let largestId = -1;
        let largestSize = 0;
        for (const [clusterId, cluster] of this.clusters) {
            if (cluster.nodes.length > largestSize) {
                largestSize = cluster.nodes.length;
                largestId = clusterId;
            }
        }
        if (largestId >= 0 && this._accountName) {
            this.clusters.get(largestId).label = this._accountName;
        }
    }

    convexHull(points) {
        if (points.length < 3) return [...points];
        const sorted = [...points].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
        const cross = (O, A, B) =>
            (A[0] - O[0]) * (B[1] - O[1]) - (A[1] - O[1]) * (B[0] - O[0]);
        const lower = [];
        for (const p of sorted) {
            while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
                lower.pop();
            }
            lower.push(p);
        }
        const upper = [];
        for (let i = sorted.length - 1; i >= 0; i--) {
            const p = sorted[i];
            while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
                upper.pop();
            }
            upper.push(p);
        }
        upper.pop();
        lower.pop();
        return lower.concat(upper);
    }

    // ─── D3 Force Simulation ────────────────────────────────────────

    initCanvas() {
        const container = this.refs.canvasContainer;
        if (!container) return;

        this.width = container.clientWidth || 800;
        this.height = container.clientHeight || 600;

        // Create canvas element
        this.canvas = document.createElement('canvas');
        this.canvas.width = this.width;
        this.canvas.height = this.height;
        this.canvas.style.width = '100%';
        this.canvas.style.height = '100%';
        container.appendChild(this.canvas);

        this.ctx = this.canvas.getContext('2d');

        // Set up event listeners
        this.canvas.addEventListener('mousemove', this.handleMouseMove.bind(this));
        this.canvas.addEventListener('mousedown', this.handleMouseDown.bind(this));
        this.canvas.addEventListener('mouseup', this.handleMouseUp.bind(this));
        this.canvas.addEventListener('click', this.handleCanvasClick.bind(this));
        this.canvas.addEventListener('wheel', this.handleWheel.bind(this), { passive: false });
        this.canvas.addEventListener('dblclick', this.handleDoubleClick.bind(this));

        // Handle resize
        this.resizeObserver = new ResizeObserver(() => {
            this.width = container.clientWidth;
            this.height = container.clientHeight;
            this.canvas.width = this.width;
            this.canvas.height = this.height;
            this.renderCanvas();
        });
        this.resizeObserver.observe(container);
    }

    startSimulation() {
        if (this.simulation) {
            this.simulation.stop();
        }

        // eslint-disable-next-line no-undef
        const d3 = window.d3;
        if (!d3) return;

        // In hierarchy mode, fix the Account node at center
        if (this.showHierarchy) {
            const accountNode = this.nodes.find(
                n => n.nodeType === 'Account' && !n.isHierarchyAccount
            );
            if (accountNode) {
                accountNode.fx = this.width / 2;
                accountNode.fy = this.height / 2;
            }
        }

        // Store reference for cluster force closure
        const clusters = this.clusters;
        const w = this.width;
        const h = this.height;

        this.simulation = d3.forceSimulation(this.nodes)
            .force('link', d3.forceLink(this.edges)
                .id(d => d.id)
                .distance(d => {
                    if (d.edgeType === 'co_occurrence') return 80;
                    if (d.edgeType === 'opportunity_role') return 150;
                    if (d.edgeType === 'cross_account') return 180;
                    if (d.edgeType === 'hierarchy') return 200;
                    if (d.edgeType === 'moved_to') return 100;
                    if (d.edgeType === 'account_relationship') return 120;
                    return 120;
                })
                .strength(d => d.strength || 0.3)
            )
            .force('charge', d3.forceManyBody()
                .strength(-300)
                .distanceMax(400)
            )
            .force('center', d3.forceCenter(w / 2, h / 2))
            .force('collision', d3.forceCollide()
                .radius(d => d.radius + 5)
            )
            .force('cluster', (alpha) => {
                // Attract same-cluster nodes toward their centroid
                if (!clusters || clusters.size <= 1) return;
                const strength = 0.15 * alpha;
                const centroids = new Map();
                for (const [cid, cluster] of clusters) {
                    let cx = 0, cy = 0;
                    for (const n of cluster.nodes) { cx += n.x; cy += n.y; }
                    centroids.set(cid, { x: cx / cluster.nodes.length, y: cy / cluster.nodes.length });
                }
                for (const node of this.nodes) {
                    if (node.clusterId == null || node.clusterId < 0 || node.fx != null) continue;
                    const centroid = centroids.get(node.clusterId);
                    if (!centroid) continue;
                    node.vx += (centroid.x - node.x) * strength;
                    node.vy += (centroid.y - node.y) * strength;
                }
            })
            .force('bounds', () => {
                // Keep nodes within the canvas
                const pad = 50;
                for (const node of this.nodes) {
                    if (node.fx != null) continue;
                    if (node.x < pad) node.vx += 1;
                    if (node.x > w - pad) node.vx -= 1;
                    if (node.y < pad) node.vy += 1;
                    if (node.y > h - pad) node.vy -= 1;
                }
            })
            .alphaDecay(0.02)
            .on('tick', () => this.renderCanvas());
    }

    // ─── Canvas Rendering ───────────────────────────────────────────

    renderCanvas() {
        if (!this.ctx) return;

        const ctx = this.ctx;
        const t = this.transform;

        ctx.save();
        ctx.clearRect(0, 0, this.width, this.height);

        // Apply zoom/pan transform
        ctx.translate(t.x, t.y);
        ctx.scale(t.k, t.k);

        // Draw cluster hulls (translucent backgrounds)
        if (this.clusters && this.clusters.size > 1) {
            for (const [, cluster] of this.clusters) {
                if (cluster.nodes.length < 2) continue;

                const points = cluster.nodes.map(n => [n.x, n.y]);
                const hull = this.convexHull(points);
                if (hull.length < 3) continue;

                // Expand hull outward by padding
                const padding = 35;
                const cx = hull.reduce((s, p) => s + p[0], 0) / hull.length;
                const cy = hull.reduce((s, p) => s + p[1], 0) / hull.length;

                ctx.beginPath();
                hull.forEach((p, i) => {
                    const dx = p[0] - cx;
                    const dy = p[1] - cy;
                    const dist = Math.sqrt(dx * dx + dy * dy) || 1;
                    const px = p[0] + (dx / dist) * padding;
                    const py = p[1] + (dy / dist) * padding;
                    if (i === 0) { ctx.moveTo(px, py); } else { ctx.lineTo(px, py); }
                });
                ctx.closePath();
                ctx.fillStyle = cluster.color;
                ctx.fill();
                ctx.strokeStyle = cluster.color.replace('0.08', '0.15');
                ctx.lineWidth = 1;
                ctx.stroke();

                // Cluster label above the hull
                const topPoint = hull.reduce((top, p) => p[1] < top[1] ? p : top, hull[0]);
                ctx.font = 'bold 11px sans-serif';
                ctx.fillStyle = 'rgba(0, 0, 0, 0.35)';
                ctx.textAlign = 'center';
                ctx.fillText(cluster.label, cx, topPoint[1] - padding - 5);
            }
        }

        // Draw edges
        this.edges.forEach(edge => {
            this.drawEdge(ctx, edge);
        });

        // Draw nodes
        this.nodes.forEach(node => {
            this.drawNode(ctx, node);
        });

        // Draw hovered node highlight
        if (this.hoveredNode) {
            this.drawNodeHighlight(ctx, this.hoveredNode);
            this.drawTooltip(ctx, this.hoveredNode);
        }

        ctx.restore();

        // Draw fixed legend (not affected by zoom/pan)
        this.drawLegend(ctx);
    }

    drawEdge(ctx, edge) {
        const source = edge.source;
        const target = edge.target;

        ctx.beginPath();
        ctx.moveTo(source.x, source.y);
        ctx.lineTo(target.x, target.y);

        // All edges are solid — color varies by type
        let edgeColor;
        if (edge.edgeType === 'co_occurrence') {
            edgeColor = 'rgba(100, 100, 100, 0.3)';
        } else if (edge.edgeType === 'opportunity_role') {
            edgeColor = 'rgba(255, 152, 0, 0.5)';
        } else if (edge.edgeType === 'cross_account') {
            edgeColor = 'rgba(0, 137, 123, 0.5)';
        } else if (edge.edgeType === 'hierarchy') {
            edgeColor = 'rgba(1, 118, 211, 0.6)';
        } else if (edge.edgeType === 'moved_to') {
            edgeColor = 'rgba(198, 40, 40, 0.7)';
        } else {
            edgeColor = 'rgba(50, 50, 50, 0.4)';
        }

        ctx.strokeStyle = edgeColor;
        ctx.lineWidth = edge.edgeType === 'hierarchy'
            ? 3
            : edge.edgeType === 'moved_to'
                ? 2.5
                : Math.max(1, (edge.strength || 0.1) * 4);
        ctx.stroke();

        // Arrow for moved_to edges (points toward the new company)
        if (edge.edgeType === 'moved_to') {
            const angle = Math.atan2(target.y - source.y, target.x - source.x);
            const arrowLen = 12;
            const arrowAngle = Math.PI / 6;
            const tipX = target.x - (target.radius + 2) * Math.cos(angle);
            const tipY = target.y - (target.radius + 2) * Math.sin(angle);

            ctx.beginPath();
            ctx.moveTo(tipX, tipY);
            ctx.lineTo(
                tipX - arrowLen * Math.cos(angle - arrowAngle),
                tipY - arrowLen * Math.sin(angle - arrowAngle)
            );
            ctx.lineTo(
                tipX - arrowLen * Math.cos(angle + arrowAngle),
                tipY - arrowLen * Math.sin(angle + arrowAngle)
            );
            ctx.closePath();
            ctx.fillStyle = edgeColor;
            ctx.fill();

            // "moved to" label on the edge
            const midX = (source.x + target.x) / 2;
            const midY = (source.y + target.y) / 2;
            ctx.font = 'bold 9px sans-serif';
            ctx.fillStyle = '#c62828';
            ctx.textAlign = 'center';
            ctx.fillText('moved to', midX, midY - 5);
        }
    }

    drawNode(ctx, node) {
        const radius = node.radius;
        const isMoved = node.hasMovedCompany === true;
        const isMovedToCompany = node.nodeType === 'Moved_To_Company';
        const isHierarchyAcct = node.isHierarchyAccount === true;

        ctx.save();

        if (isHierarchyAcct) {
            ctx.globalAlpha = 0.7;
        }

        ctx.beginPath();

        if (node.nodeType === 'Account' || isMovedToCompany) {
            // Diamond shape
            ctx.moveTo(node.x, node.y - radius);
            ctx.lineTo(node.x + radius, node.y);
            ctx.lineTo(node.x, node.y + radius);
            ctx.lineTo(node.x - radius, node.y);
            ctx.closePath();
        } else if (node.nodeType === 'Opportunity') {
            // Square shape
            ctx.rect(node.x - radius, node.y - radius, radius * 2, radius * 2);
        } else if (node.nodeType === 'External_Contact') {
            // Hexagon shape
            for (let i = 0; i < 6; i++) {
                const angle = (Math.PI / 3) * i - Math.PI / 2;
                const px = node.x + radius * Math.cos(angle);
                const py = node.y + radius * Math.sin(angle);
                if (i === 0) { ctx.moveTo(px, py); } else { ctx.lineTo(px, py); }
            }
            ctx.closePath();
        } else {
            // Circle for contacts
            ctx.arc(node.x, node.y, radius, 0, 2 * Math.PI);
        }

        // Fill color (node.color already handles moved = grey)
        ctx.fillStyle = node.color;
        ctx.fill();

        // Border
        if (isMoved) {
            ctx.strokeStyle = '#c62828';
            ctx.lineWidth = 3;
        } else if (isMovedToCompany) {
            ctx.strokeStyle = '#c62828';
            ctx.lineWidth = 2;
            ctx.setLineDash([4, 3]);
        } else if (isHierarchyAcct && node.hierarchyLevel === 'parent') {
            ctx.strokeStyle = '#003d73';
            ctx.lineWidth = 3;
        } else {
            ctx.strokeStyle = '#fff';
            ctx.lineWidth = 2;
        }
        ctx.stroke();
        ctx.setLineDash([]);

        // Moved contacts: bold red diagonal line through the node
        if (isMoved) {
            ctx.beginPath();
            ctx.moveTo(node.x - radius * 0.7, node.y - radius * 0.7);
            ctx.lineTo(node.x + radius * 0.7, node.y + radius * 0.7);
            ctx.strokeStyle = '#c62828';
            ctx.lineWidth = 3;
            ctx.stroke();
        }

        // Risk ring indicator (dashed ring is ok per user)
        if (node.nodeType === 'Contact' && this.riskNodeIds.has(node.id)) {
            const severity = this.riskNodeIds.get(node.id);
            ctx.globalAlpha = 1;
            ctx.beginPath();
            ctx.arc(node.x, node.y, radius + 5, 0, 2 * Math.PI);
            ctx.strokeStyle = severity === 'high' ? '#c62828' : '#ef6c00';
            ctx.lineWidth = 2.5;
            ctx.setLineDash([4, 3]);
            ctx.stroke();
            ctx.setLineDash([]);
        }

        ctx.restore();

        // Node label
        if (node.nodeType === 'Account' || isMovedToCompany) {
            ctx.font = 'bold 12px sans-serif';
            ctx.fillStyle = isMovedToCompany ? '#c62828' : '#333';
        } else {
            ctx.font = '10px sans-serif';
            ctx.fillStyle = isMoved ? '#999' : '#333';
        }
        ctx.textAlign = 'center';

        // Truncate long names
        const maxChars = 15;
        const label = node.name.length > maxChars
            ? node.name.substring(0, maxChars) + '...'
            : node.name;

        const labelY = node.y + radius + 14;
        ctx.fillText(label, node.x, labelY);

        // Moved contacts: red "LEFT" badge below name
        if (isMoved) {
            const badgeY = labelY + 12;
            const badgeText = 'LEFT';
            ctx.font = 'bold 9px sans-serif';
            const badgeW = ctx.measureText(badgeText).width + 8;
            const badgeH = 14;
            const badgeX = node.x - badgeW / 2;

            // Red pill background
            ctx.beginPath();
            ctx.roundRect(badgeX, badgeY - 10, badgeW, badgeH, 3);
            ctx.fillStyle = '#c62828';
            ctx.fill();

            // White text
            ctx.fillStyle = '#fff';
            ctx.textAlign = 'center';
            ctx.fillText(badgeText, node.x, badgeY);
        }
    }

    drawNodeHighlight(ctx, node) {
        ctx.beginPath();
        ctx.arc(node.x, node.y, node.radius + 4, 0, 2 * Math.PI);
        ctx.strokeStyle = '#0176d3';
        ctx.lineWidth = 3;
        ctx.stroke();
    }

    drawTooltip(ctx, node) {
        const lines = [node.name];
        if (node.nodeType === 'Moved_To_Company') {
            lines.push('Contact moved here');
        }
        if (node.title) lines.push(node.title);
        if (node.hasMovedCompany) {
            lines.push('\u274C No longer at company');
            if (node.previousCompany) lines.push('Moved to: ' + node.previousCompany);
        }
        if (node.isHierarchyAccount) {
            const level = node.hierarchyLevel === 'parent' ? 'Parent Account' : 'Child Account';
            lines.push(level);
        }
        if (node.nodeType === 'External_Contact' && node.accountName) {
            lines.push('Account: ' + node.accountName);
        } else if (node.nodeType === 'Opportunity' && node.classification) {
            lines.push('Stage: ' + node.classification);
            if (node.amount != null) {
                lines.push('$' + Number(node.amount).toLocaleString());
            }
        } else if (node.classification && node.classification !== 'Unknown') {
            lines.push(node.classification);
        }
        if (node.interactionCount) {
            const label = node.nodeType === 'External_Contact'
                ? ' shared interactions' : ' interactions';
            lines.push(node.interactionCount + label);
        }

        const padding = 8;
        const lineHeight = 16;
        const tooltipWidth = Math.max(...lines.map(l => ctx.measureText(l).width)) + padding * 2;
        const tooltipHeight = lines.length * lineHeight + padding * 2;
        const tooltipX = node.x + node.radius + 10;
        const tooltipY = node.y - tooltipHeight / 2;

        // Background
        ctx.fillStyle = 'rgba(255, 255, 255, 0.95)';
        ctx.strokeStyle = '#ddd';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.roundRect(tooltipX, tooltipY, tooltipWidth, tooltipHeight, 4);
        ctx.fill();
        ctx.stroke();

        // Text
        ctx.font = '11px sans-serif';
        ctx.fillStyle = '#333';
        ctx.textAlign = 'left';
        lines.forEach((line, i) => {
            ctx.fillText(line, tooltipX + padding, tooltipY + padding + (i + 1) * lineHeight - 4);
        });
    }

    drawLegend(ctx) {
        // Only show legend items relevant to the current graph
        const legendItems = [];
        if (this.riskNodeIds && this.riskNodeIds.size > 0) {
            legendItems.push({ type: 'ring', color: '#c62828', label: 'At-risk (dashed ring)' });
        }
        if (this.movedContactCount > 0) {
            legendItems.push({ type: 'moved', label: 'Left company' });
        }
        const hasMovedToEdge = this.edges && this.edges.some(e => e.edgeType === 'moved_to');
        if (hasMovedToEdge) {
            legendItems.push({ type: 'arrow', label: 'Moved to (new company)' });
        }

        if (legendItems.length === 0) return;

        const padding = 8;
        const lineHeight = 18;
        const legendW = 210;
        const legendH = legendItems.length * lineHeight + padding * 2;
        const legendX = 12;
        const legendY = 12;

        // Background
        ctx.fillStyle = 'rgba(255, 255, 255, 0.92)';
        ctx.strokeStyle = '#ddd';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.roundRect(legendX, legendY, legendW, legendH, 6);
        ctx.fill();
        ctx.stroke();

        ctx.font = '10px sans-serif';
        ctx.textAlign = 'left';

        legendItems.forEach((item, i) => {
            const y = legendY + padding + i * lineHeight + 10;
            const iconX = legendX + padding;
            const textX = iconX + 36;

            if (item.type === 'ring') {
                ctx.beginPath();
                ctx.arc(iconX + 14, y, 7, 0, 2 * Math.PI);
                ctx.strokeStyle = item.color;
                ctx.lineWidth = 2;
                ctx.setLineDash([3, 2]);
                ctx.stroke();
                ctx.setLineDash([]);
            } else if (item.type === 'moved') {
                // Grey circle with red border + diagonal line
                ctx.beginPath();
                ctx.arc(iconX + 14, y, 7, 0, 2 * Math.PI);
                ctx.fillStyle = '#bdbdbd';
                ctx.fill();
                ctx.strokeStyle = '#c62828';
                ctx.lineWidth = 2;
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(iconX + 9, y - 5);
                ctx.lineTo(iconX + 19, y + 5);
                ctx.strokeStyle = '#c62828';
                ctx.lineWidth = 2;
                ctx.stroke();
            } else if (item.type === 'arrow') {
                // Red line with arrowhead
                ctx.beginPath();
                ctx.moveTo(iconX, y);
                ctx.lineTo(iconX + 22, y);
                ctx.strokeStyle = '#c62828';
                ctx.lineWidth = 2;
                ctx.stroke();
                // Arrowhead
                ctx.beginPath();
                ctx.moveTo(iconX + 28, y);
                ctx.lineTo(iconX + 20, y - 5);
                ctx.lineTo(iconX + 20, y + 5);
                ctx.closePath();
                ctx.fillStyle = '#c62828';
                ctx.fill();
            }

            ctx.fillStyle = '#555';
            ctx.fillText(item.label, textX, y + 3);
        });
    }

    // ─── Node Styling ───────────────────────────────────────────────

    getNodeRadius(node) {
        if (node.nodeType === 'Moved_To_Company') return 18;
        if (node.nodeType === 'Account') {
            if (node.isHierarchyAccount) {
                return node.hierarchyLevel === 'parent' ? 30 : 16;
            }
            return 24;
        }
        if (node.nodeType === 'Opportunity') return 14;
        if (node.nodeType === 'External_Contact') {
            const base = 8;
            const maxExtra = 8;
            const interactions = node.interactionCount || 0;
            return base + Math.min(interactions / 5, maxExtra);
        }

        // Contact radius based on interaction count
        const base = 10;
        const maxExtra = 12;
        const interactions = node.interactionCount || 0;
        return base + Math.min(interactions / 5, maxExtra);
    }

    getNodeColor(node) {
        // Moved contacts are always grey
        if (node.hasMovedCompany === true) {
            return '#bdbdbd';
        }
        if (node.nodeType === 'Moved_To_Company') {
            return '#e8e8e8';
        }
        if (node.nodeType === 'External_Contact') {
            return NODE_TYPE_COLORS['External_Contact'];
        }
        if (node.nodeType === 'Account' && node.isHierarchyAccount) {
            return node.hierarchyLevel === 'parent' ? '#005FB2' : '#57A3E8';
        }
        if (node.nodeType !== 'Contact') {
            return NODE_TYPE_COLORS[node.nodeType] || '#9e9e9e';
        }

        // Contact color based on classification
        if (this.activeFilters.length > 0 && !this.activeFilters.includes(node.classification)) {
            return '#e0e0e0'; // Dimmed for filtered-out classifications
        }

        return CLASSIFICATION_COLORS[node.classification] || CLASSIFICATION_COLORS['Unknown'];
    }

    // ─── Event Handlers ─────────────────────────────────────────────

    handleMouseMove(event) {
        const rect = this.canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left - this.transform.x) / this.transform.k;
        const y = (event.clientY - rect.top - this.transform.y) / this.transform.k;

        // Handle dragging
        if (this.draggedNode) {
            this.draggedNode.fx = x;
            this.draggedNode.fy = y;
            if (this.simulation) this.simulation.alpha(0.3).restart();
            return;
        }

        // Handle panning
        if (this.isPanning) {
            this.transform.x += event.movementX;
            this.transform.y += event.movementY;
            this.renderCanvas();
            return;
        }

        // Hit test for hover
        const node = this.findNodeAt(x, y);
        if (node !== this.hoveredNode) {
            this.hoveredNode = node;
            this.canvas.style.cursor = node ? 'pointer' : 'default';
            this.renderCanvas();
        }
    }

    handleMouseDown(event) {
        const rect = this.canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left - this.transform.x) / this.transform.k;
        const y = (event.clientY - rect.top - this.transform.y) / this.transform.k;

        const node = this.findNodeAt(x, y);
        if (node) {
            this.draggedNode = node;
            node.fx = node.x;
            node.fy = node.y;
            if (this.simulation) this.simulation.alphaTarget(0.3).restart();
        } else {
            this.isPanning = true;
        }
    }

    handleMouseUp() {
        if (this.draggedNode) {
            this.draggedNode.fx = null;
            this.draggedNode.fy = null;
            // Only re-fix account node in hierarchy mode
            if (this.showHierarchy && this.draggedNode.nodeType === 'Account' && !this.draggedNode.isHierarchyAccount) {
                this.draggedNode.fx = this.draggedNode.x;
                this.draggedNode.fy = this.draggedNode.y;
            }
            this.draggedNode = null;
            if (this.simulation) this.simulation.alphaTarget(0);
        }
        this.isPanning = false;
    }

    handleCanvasClick(event) {
        const rect = this.canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left - this.transform.x) / this.transform.k;
        const y = (event.clientY - rect.top - this.transform.y) / this.transform.k;

        const node = this.findNodeAt(x, y);
        if (node) {
            this.selectedNode = { ...node };
        } else {
            this.selectedNode = null;
        }
    }

    handleDoubleClick(event) {
        const rect = this.canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left - this.transform.x) / this.transform.k;
        const y = (event.clientY - rect.top - this.transform.y) / this.transform.k;

        const node = this.findNodeAt(x, y);
        if (node) {
            this.navigateToRecordById(node.id);
        }
    }

    handleWheel(event) {
        event.preventDefault();

        const rect = this.canvas.getBoundingClientRect();
        const mouseX = event.clientX - rect.left;
        const mouseY = event.clientY - rect.top;

        const scaleFactor = event.deltaY < 0 ? 1.05 : 1 / 1.05;
        const newK = Math.max(0.1, Math.min(5, this.transform.k * scaleFactor));

        // Zoom toward mouse position
        this.transform.x = mouseX - (mouseX - this.transform.x) * (newK / this.transform.k);
        this.transform.y = mouseY - (mouseY - this.transform.y) * (newK / this.transform.k);
        this.transform.k = newK;

        this.renderCanvas();
    }

    findNodeAt(x, y) {
        // Search in reverse (top nodes first)
        for (let i = this.nodes.length - 1; i >= 0; i--) {
            const node = this.nodes[i];
            const dx = x - node.x;
            const dy = y - node.y;
            if (dx * dx + dy * dy < node.radius * node.radius) {
                return node;
            }
        }
        return null;
    }

    // ─── UI Actions ─────────────────────────────────────────────────

    async handleRefresh() {
        this.isLoading = true;
        try {
            const data = await refreshGraphData({
                accountId: this.recordId,
                hidePassive: this.hidePassive,
                minInteractions: this.minInteractions,
                thresholdDays: this.config.activityThresholdDays || 90,
                showExternalContacts: this.showExternalContacts,
                showHierarchy: this.showHierarchy
            });
            this.processGraphData(data);
            this.showToast('Success', 'Graph data refreshed', 'success');
        } catch (error) {
            this.showError('Failed to refresh: ' + this.extractErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    toggleHidePassive() {
        this.hidePassive = !this.hidePassive;
        this._saveToggleState();
        this.loadGraphData();
    }

    toggleExternalContacts() {
        this.showExternalContacts = !this.showExternalContacts;
        this._saveToggleState();
        this.loadGraphData();
    }

    toggleHierarchy() {
        this.showHierarchy = !this.showHierarchy;
        this._saveToggleState();
        this.loadGraphData();
    }

    handleThresholdChange(event) {
        this.minInteractions = event.detail.value;
        this._saveToggleState();
        // Debounce: reload after user stops sliding
        clearTimeout(this._thresholdTimeout);
        this._thresholdTimeout = setTimeout(() => {
            this.loadGraphData();
        }, 500);
    }

    handleFilterClick(event) {
        const classification = event.currentTarget.dataset.classification;
        const idx = this.activeFilters.indexOf(classification);
        if (idx >= 0) {
            this.activeFilters = this.activeFilters.filter(f => f !== classification);
        } else {
            this.activeFilters = [...this.activeFilters, classification];
        }
        // Update node colors
        this.nodes.forEach(n => {
            n.color = this.getNodeColor(n);
        });
        this.renderCanvas();
    }

    async handleClassificationOverride(event) {
        const newClassification = event.detail.value;
        if (!this.selectedNode) return;

        try {
            await overrideClassification({
                contactId: this.selectedNode.id,
                accountId: this.recordId,
                classification: newClassification
            });

            // Update local state
            this.selectedNode.classification = newClassification;
            const node = this.nodes.find(n => n.id === this.selectedNode.id);
            if (node) {
                node.classification = newClassification;
                node.color = this.getNodeColor(node);
            }
            this.renderCanvas();

            this.showToast('Success', 'Classification updated', 'success');
        } catch (error) {
            this.showError('Failed to override classification: ' + this.extractErrorMessage(error));
        }
    }

    closeDetailPanel() {
        this.selectedNode = null;
    }

    handleRiskAlertToggle() {
        this.showRiskPanel = !this.showRiskPanel;
    }

    closeRiskPanel() {
        this.showRiskPanel = false;
    }

    handleRiskAlertClick(event) {
        const contactId = event.currentTarget.dataset.contactId;
        if (!contactId) return;

        // Find and select the node
        const node = this.nodes.find(n => n.id === contactId);
        if (node) {
            this.selectedNode = { ...node };

            // Center canvas on the node
            this.transform.x = this.width / 2 - node.x * this.transform.k;
            this.transform.y = this.height / 2 - node.y * this.transform.k;
            this.renderCanvas();
        }
    }

    handleZoomIn() {
        this._applyZoom(1.2);
    }

    handleZoomOut() {
        this._applyZoom(1 / 1.2);
    }

    handleZoomReset() {
        this.transform = { x: 0, y: 0, k: 1 };
        this.renderCanvas();
    }

    _applyZoom(factor) {
        const centerX = this.width / 2;
        const centerY = this.height / 2;
        const newK = Math.max(0.1, Math.min(5, this.transform.k * factor));
        this.transform.x = centerX - (centerX - this.transform.x) * (newK / this.transform.k);
        this.transform.y = centerY - (centerY - this.transform.y) * (newK / this.transform.k);
        this.transform.k = newK;
        this.renderCanvas();
    }

    navigateToRecord() {
        if (this.selectedNode) {
            this.navigateToRecordById(this.selectedNode.id);
        }
    }

    navigateToRecordById(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    // ─── Computed Properties ────────────────────────────────────────

    get hidePassiveLabel() {
        return this.hidePassive ? 'Show All' : 'Hide Passive';
    }

    get hidePassiveIcon() {
        return this.hidePassive ? 'utility:preview' : 'utility:hide';
    }

    get hidePassiveVariant() {
        return this.hidePassive ? 'brand' : 'neutral';
    }

    get nodeCount() {
        return this.nodes ? this.nodes.length : 0;
    }

    get edgeCount() {
        return this.edges ? this.edges.length : 0;
    }

    get isContactNode() {
        return this.selectedNode && this.selectedNode.nodeType === 'Contact';
    }

    get isOpportunityNode() {
        return this.selectedNode && this.selectedNode.nodeType === 'Opportunity';
    }

    get isExternalContactNode() {
        return this.selectedNode && this.selectedNode.nodeType === 'External_Contact';
    }

    get showExternalLabel() {
        return this.showExternalContacts ? 'Hide External' : 'Show External';
    }

    get showExternalVariant() {
        return this.showExternalContacts ? 'brand' : 'neutral';
    }

    get showHierarchyLabel() {
        return this.showHierarchy ? 'Hide Hierarchy' : 'Show Hierarchy';
    }

    get showHierarchyVariant() {
        return this.showHierarchy ? 'brand' : 'neutral';
    }

    get clusterCount() {
        return this.clusters ? this.clusters.size : 0;
    }

    get isHierarchyAccountNode() {
        return this.selectedNode && this.selectedNode.isHierarchyAccount === true;
    }

    get formattedHierarchyLevel() {
        if (!this.selectedNode || !this.selectedNode.hierarchyLevel) return '';
        const level = this.selectedNode.hierarchyLevel;
        return level.charAt(0).toUpperCase() + level.slice(1) + ' Account';
    }

    get selectedNodeHasMoved() {
        return this.selectedNode && this.selectedNode.hasMovedCompany === true;
    }

    get formattedAmount() {
        if (!this.selectedNode || this.selectedNode.amount == null) return null;
        return new Intl.NumberFormat('en-US', {
            style: 'currency', currency: 'USD', maximumFractionDigits: 0
        }).format(this.selectedNode.amount);
    }

    get formattedCloseDate() {
        if (!this.selectedNode || !this.selectedNode.closeDate) return null;
        return this.selectedNode.closeDate;
    }

    get hasStrengthFactors() {
        return this.strengthFactors.length > 0;
    }

    get strengthFactors() {
        if (!this.selectedNode || !this.selectedNode.strengthFactors) return [];
        const factors = this.selectedNode.strengthFactors
            .filter(f => f.contribution > 0)
            .sort((a, b) => b.contribution - a.contribution);
        const maxContribution = factors.length > 0
            ? Math.max(...factors.map(f => f.contribution), 0.01)
            : 1;
        return factors.map((f, idx) => ({
            ...f,
            key: 'factor-' + idx,
            formattedContribution: f.contribution.toFixed(1),
            barStyle: `width: ${Math.min(100, (f.contribution / maxContribution) * 100)}%`
        }));
    }

    get formattedConfidence() {
        if (!this.selectedNode || !this.selectedNode.confidence) return '0';
        return Math.round(this.selectedNode.confidence * 100);
    }

    get selectedNodeClassificationClass() {
        const cls = this.selectedNode?.classification || 'Unknown';
        return 'classification-badge classification-' + cls.toLowerCase().replace(/\s+/g, '-');
    }

    get riskAlertCount() {
        return this.riskAlerts.length;
    }

    get hasRiskAlerts() {
        return this.riskAlerts.length > 0;
    }

    get riskAlertButtonVariant() {
        return this.riskAlerts.some(a => a.severity === 'high') ? 'destructive' : 'neutral';
    }

    get riskAlertButtonLabel() {
        return this.riskAlerts.length + ' Risk' + (this.riskAlerts.length !== 1 ? 's' : '');
    }

    get classificationFilters() {
        const hasActiveFilters = this.activeFilters.length > 0;
        return Object.keys(CLASSIFICATION_COLORS).map(cls => {
            const isActive = this.activeFilters.includes(cls);
            let cssClass = 'filter-badge';
            if (hasActiveFilters) {
                cssClass += isActive ? ' filter-active' : ' filter-dimmed';
            }
            const color = CLASSIFICATION_COLORS[cls];
            return {
                value: cls,
                label: cls,
                cssClass,
                badgeStyle: `background-color: ${color}; color: #fff;`
            };
        });
    }

    get classificationOptions() {
        return Object.keys(CLASSIFICATION_COLORS).map(cls => ({
            label: cls,
            value: cls
        }));
    }

    // ─── Helpers ────────────────────────────────────────────────────

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error'
        }));
    }

    extractErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'Unknown error';
    }
}
