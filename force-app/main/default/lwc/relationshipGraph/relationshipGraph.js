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
    'Opportunity': 'square'
};

const NODE_TYPE_COLORS = {
    'Account': '#0176d3',
    'Opportunity': '#ff9800'
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
    riskNodeIds = new Map(); // nodeId → highest severity

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

    connectedCallback() {
        this.hidePassive = !this.showAllContacts;
        this.minInteractions = this.defaultMinInteractions;
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
                thresholdDays: this.config.activityThresholdDays || 90
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

        // Convert to D3-compatible format
        this.nodes = data.nodes.map(n => ({
            ...n,
            x: this.width / 2 + (Math.random() - 0.5) * 200,
            y: this.height / 2 + (Math.random() - 0.5) * 200,
            radius: this.getNodeRadius(n),
            color: this.getNodeColor(n)
        }));

        // Build node ID map for edge resolution
        const nodeMap = new Map();
        this.nodes.forEach(n => nodeMap.set(n.id, n));

        this.edges = data.edges
            .filter(e => nodeMap.has(e.source) && nodeMap.has(e.target))
            .map(e => ({
                ...e,
                source: nodeMap.get(e.source),
                target: nodeMap.get(e.target)
            }));

        this.startSimulation();
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

        // Find the account node (center)
        const accountNode = this.nodes.find(n => n.nodeType === 'Account');
        if (accountNode) {
            accountNode.fx = this.width / 2;
            accountNode.fy = this.height / 2;
        }

        this.simulation = d3.forceSimulation(this.nodes)
            .force('link', d3.forceLink(this.edges)
                .id(d => d.id)
                .distance(d => {
                    if (d.edgeType === 'co_occurrence') return 100;
                    if (d.edgeType === 'opportunity_role') return 150;
                    return 120;
                })
                .strength(d => d.strength || 0.3)
            )
            .force('charge', d3.forceManyBody()
                .strength(-200)
                .distanceMax(400)
            )
            .force('center', d3.forceCenter(this.width / 2, this.height / 2))
            .force('collision', d3.forceCollide()
                .radius(d => d.radius + 5)
            )
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
    }

    drawEdge(ctx, edge) {
        const source = edge.source;
        const target = edge.target;

        ctx.beginPath();
        ctx.moveTo(source.x, source.y);
        ctx.lineTo(target.x, target.y);

        // Edge style based on type
        if (edge.edgeType === 'co_occurrence') {
            ctx.strokeStyle = 'rgba(100, 100, 100, 0.3)';
            ctx.setLineDash([4, 4]);
        } else if (edge.edgeType === 'opportunity_role') {
            ctx.strokeStyle = 'rgba(255, 152, 0, 0.5)';
            ctx.setLineDash([]);
        } else {
            ctx.strokeStyle = 'rgba(50, 50, 50, 0.4)';
            ctx.setLineDash([]);
        }

        // Edge width based on strength
        ctx.lineWidth = Math.max(1, (edge.strength || 0.1) * 4);
        ctx.stroke();
        ctx.setLineDash([]);

        // Draw co-occurrence count label
        if (edge.edgeType === 'co_occurrence' && edge.interactionCount > 1) {
            const midX = (source.x + target.x) / 2;
            const midY = (source.y + target.y) / 2;
            ctx.font = '9px sans-serif';
            ctx.fillStyle = '#666';
            ctx.textAlign = 'center';
            ctx.fillText(edge.interactionCount.toString(), midX, midY - 3);
        }
    }

    drawNode(ctx, node) {
        const radius = node.radius;

        ctx.beginPath();

        if (node.nodeType === 'Account') {
            // Diamond shape
            ctx.moveTo(node.x, node.y - radius);
            ctx.lineTo(node.x + radius, node.y);
            ctx.lineTo(node.x, node.y + radius);
            ctx.lineTo(node.x - radius, node.y);
            ctx.closePath();
        } else if (node.nodeType === 'Opportunity') {
            // Square shape
            ctx.rect(node.x - radius, node.y - radius, radius * 2, radius * 2);
        } else {
            // Circle for contacts
            ctx.arc(node.x, node.y, radius, 0, 2 * Math.PI);
        }

        ctx.fillStyle = node.color;
        ctx.fill();

        // Border
        ctx.strokeStyle = '#fff';
        ctx.lineWidth = 2;
        ctx.stroke();

        // Risk ring indicator
        if (node.nodeType === 'Contact' && this.riskNodeIds.has(node.id)) {
            const severity = this.riskNodeIds.get(node.id);
            ctx.beginPath();
            ctx.arc(node.x, node.y, radius + 5, 0, 2 * Math.PI);
            ctx.strokeStyle = severity === 'high' ? '#c62828' : '#ef6c00';
            ctx.lineWidth = 2.5;
            ctx.setLineDash([4, 3]);
            ctx.stroke();
            ctx.setLineDash([]);
        }

        // Node label
        ctx.font = node.nodeType === 'Account' ? 'bold 12px sans-serif' : '10px sans-serif';
        ctx.fillStyle = '#333';
        ctx.textAlign = 'center';

        // Truncate long names
        const maxChars = 15;
        const label = node.name.length > maxChars
            ? node.name.substring(0, maxChars) + '...'
            : node.name;

        ctx.fillText(label, node.x, node.y + radius + 14);
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
        if (node.title) lines.push(node.title);
        if (node.nodeType === 'Opportunity' && node.classification) {
            lines.push('Stage: ' + node.classification);
            if (node.amount != null) {
                lines.push('$' + Number(node.amount).toLocaleString());
            }
        } else if (node.classification && node.classification !== 'Unknown') {
            lines.push(node.classification);
        }
        if (node.interactionCount) {
            lines.push(node.interactionCount + ' interactions');
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

    // ─── Node Styling ───────────────────────────────────────────────

    getNodeRadius(node) {
        if (node.nodeType === 'Account') return 24;
        if (node.nodeType === 'Opportunity') return 14;

        // Contact radius based on interaction count
        const base = 10;
        const maxExtra = 12;
        const interactions = node.interactionCount || 0;
        return base + Math.min(interactions / 5, maxExtra);
    }

    getNodeColor(node) {
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
            // Keep account node fixed
            if (this.draggedNode.nodeType === 'Account') {
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
                thresholdDays: this.config.activityThresholdDays || 90
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
        this.loadGraphData();
    }

    handleThresholdChange(event) {
        this.minInteractions = event.detail.value;
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
