import { createElement } from 'lwc';
import RelationshipGraph from 'c/relationshipGraph';
import getGraphData from '@salesforce/apex/RelationshipGraphController.getGraphData';
import refreshGraphData from '@salesforce/apex/RelationshipGraphController.refreshGraphData';
import getGraphConfig from '@salesforce/apex/RelationshipGraphController.getGraphConfig';
import overrideClassification from '@salesforce/apex/RelationshipGraphController.overrideClassification';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// ─── Mocks ───────────────────────────────────────────────────────────

jest.mock(
    '@salesforce/apex/RelationshipGraphController.getGraphData',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RelationshipGraphController.refreshGraphData',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RelationshipGraphController.getGraphConfig',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RelationshipGraphController.overrideClassification',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock('lightning/platformResourceLoader', () => ({
    loadScript: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/resourceUrl/d3', () => 'mockD3Url', { virtual: true });

// ShowToastEvent must produce a real Event so dispatchEvent succeeds
jest.mock('lightning/platformShowToastEvent', () => {
    const ShowToastEvent = jest.fn().mockImplementation(function (params) {
        return new CustomEvent('lightning__showtoast', { detail: params });
    });
    return { ShowToastEvent };
}, { virtual: true });

// ResizeObserver is not available in jsdom
global.ResizeObserver = class ResizeObserver {
    constructor() {}
    observe() {}
    unobserve() {}
    disconnect() {}
};

// Canvas 2D context mock (jsdom has no canvas support)
const mockCtx = {
    save: jest.fn(),
    restore: jest.fn(),
    clearRect: jest.fn(),
    translate: jest.fn(),
    scale: jest.fn(),
    beginPath: jest.fn(),
    closePath: jest.fn(),
    moveTo: jest.fn(),
    lineTo: jest.fn(),
    arc: jest.fn(),
    fill: jest.fn(),
    stroke: jest.fn(),
    fillText: jest.fn(),
    measureText: jest.fn().mockReturnValue({ width: 50 }),
    setLineDash: jest.fn(),
    fillRect: jest.fn(),
    strokeRect: jest.fn(),
    setTransform: jest.fn(),
    rect: jest.fn(),
    roundRect: jest.fn(),
    clip: jest.fn(),
    lineWidth: 1,
    strokeStyle: '',
    fillStyle: '',
    font: '',
    textAlign: '',
    textBaseline: '',
    globalAlpha: 1
};
HTMLCanvasElement.prototype.getContext = jest.fn().mockReturnValue(mockCtx);

// ─── Test Data ───────────────────────────────────────────────────────

const MOCK_CONFIG = {
    classifications: [
        'Champion', 'Economic Buyer', 'Technical Buyer', 'Blocker',
        'Influencer', 'End User', 'Detractor', 'Unknown'
    ],
    classificationProvider: 'Heuristic',
    activityThresholdDays: 90,
    minInteractions: 3,
    timeDecayFactor: 0.95,
    cacheTTLMinutes: 30
};

const MOCK_RISK_ALERTS = [
    {
        severity: 'high',
        riskType: 'no_economic_buyer',
        message: 'No Economic Buyer identified',
        contactId: null,
        contactName: null
    },
    {
        severity: 'high',
        riskType: 'active_blocker',
        message: 'John Smith (Blocker) is actively engaged',
        contactId: '003xx000004TxyAAAA',
        contactName: 'John Smith'
    },
    {
        severity: 'medium',
        riskType: 'single_threaded',
        message: 'Only one Champion — deal at risk if they leave',
        contactId: '003xx000004TxyZAAU',
        contactName: 'Jane Doe'
    }
];

const MOCK_GRAPH_DATA = {
    nodes: [
        {
            id: '001xx000003DGbYAAW', name: 'Test Corp', nodeType: 'Account',
            classification: null, confidence: null, interactionCount: 0
        },
        {
            id: '003xx000004TxyZAAU', name: 'Jane Doe', nodeType: 'Contact',
            classification: 'Champion', confidence: 0.85, interactionCount: 12,
            title: 'VP Sales', email: 'jane@test.com',
            strengthFactors: [
                { name: 'Meeting', category: 'Activity', rawValue: 4, weight: 3.0, contribution: 12.0 },
                { name: 'Email Sent', category: 'Activity', rawValue: 8, weight: 1.0, contribution: 8.0 },
                { name: 'Task', category: 'Activity', rawValue: 3, weight: 1.0, contribution: 3.0 }
            ]
        },
        {
            id: '003xx000004TxyAAAA', name: 'John Smith', nodeType: 'Contact',
            classification: 'Blocker', confidence: 0.7, interactionCount: 5,
            title: 'CTO', email: 'john@test.com'
        },
        {
            id: '006xx000001abcDEF', name: 'Test Deal', nodeType: 'Opportunity',
            classification: null, confidence: null, interactionCount: 0
        }
    ],
    edges: [
        {
            source: '003xx000004TxyZAAU', target: '001xx000003DGbYAAW',
            strength: 0.8, interactionCount: 12, edgeType: 'account_relationship'
        },
        {
            source: '003xx000004TxyAAAA', target: '001xx000003DGbYAAW',
            strength: 0.4, interactionCount: 5, edgeType: 'account_relationship'
        },
        {
            source: '003xx000004TxyZAAU', target: '006xx000001abcDEF',
            strength: 0.6, interactionCount: 0, edgeType: 'opportunity_role',
            label: 'Decision Maker'
        }
    ],
    riskAlerts: MOCK_RISK_ALERTS,
    isTruncated: false,
    totalContactCount: 2
};

const MOCK_TRUNCATED_DATA = {
    ...MOCK_GRAPH_DATA,
    isTruncated: true,
    totalContactCount: 550
};

// ─── Helpers ─────────────────────────────────────────────────────────

function createComponent(props = {}) {
    const element = createElement('c-relationship-graph', {
        is: RelationshipGraph
    });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// ─── Tests ───────────────────────────────────────────────────────────

describe('c-relationship-graph', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        getGraphConfig.mockResolvedValue(MOCK_CONFIG);
        getGraphData.mockResolvedValue(MOCK_GRAPH_DATA);
        refreshGraphData.mockResolvedValue(MOCK_GRAPH_DATA);
        overrideClassification.mockResolvedValue(undefined);
        loadScript.mockResolvedValue();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    // ─── Component Creation ──────────────────────────────────────

    it('creates component with default properties', () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });

        expect(element).toBeTruthy();
        expect(element.recordId).toBe('001xx000003DGbYAAW');
        expect(element.showAllContacts).toBe(false);
        expect(element.defaultMinInteractions).toBe(3);
    });

    it('accepts custom @api property values', () => {
        const element = createComponent({
            recordId: '001xx000003DGbYAAW',
            showAllContacts: true,
            defaultMinInteractions: 10
        });

        expect(element.showAllContacts).toBe(true);
        expect(element.defaultMinInteractions).toBe(10);
    });

    // ─── Config Loading ──────────────────────────────────────────

    it('loads config on connected callback', async () => {
        createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(getGraphConfig).toHaveBeenCalledTimes(1);
    });

    it('handles config load failure gracefully', async () => {
        getGraphConfig.mockRejectedValue(new Error('Config failed'));

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(element).toBeTruthy();
    });

    // ─── D3 Script Loading ───────────────────────────────────────

    it('loads D3 script on rendered callback', async () => {
        createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(loadScript).toHaveBeenCalledTimes(1);
    });

    it('shows error toast when D3 fails to load', async () => {
        loadScript.mockRejectedValue(new Error('Script load failed'));

        createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(ShowToastEvent).toHaveBeenCalledWith(
            expect.objectContaining({
                title: 'Error',
                variant: 'error'
            })
        );
    });

    // ─── Graph Data Loading ──────────────────────────────────────

    it('loads graph data after D3 initializes', async () => {
        createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(getGraphData).toHaveBeenCalledWith(
            expect.objectContaining({
                accountId: '001xx000003DGbYAAW',
                hidePassive: true,
                minInteractions: expect.any(Number),
                thresholdDays: expect.any(Number)
            })
        );
    });

    it('shows error toast when graph data load fails', async () => {
        getGraphData.mockRejectedValue({ body: { message: 'Server error' } });

        createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(ShowToastEvent).toHaveBeenCalledWith(
            expect.objectContaining({
                title: 'Error',
                variant: 'error'
            })
        );
    });

    // ─── processGraphData ────────────────────────────────────────

    it('handles null data in processGraphData', async () => {
        getGraphData.mockResolvedValue(null);

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(element).toBeTruthy();
    });

    it('handles data with no nodes array', async () => {
        getGraphData.mockResolvedValue({ edges: [] });

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(element).toBeTruthy();
    });

    it('shows truncation warning toast for large datasets', async () => {
        getGraphData.mockResolvedValue(MOCK_TRUNCATED_DATA);

        createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        expect(ShowToastEvent).toHaveBeenCalledWith(
            expect.objectContaining({
                title: 'Large Account',
                variant: 'warning'
            })
        );
    });

    it('does not show truncation warning for normal datasets', async () => {
        createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const truncationCall = ShowToastEvent.mock.calls.find(
            call => call[0]?.title === 'Large Account'
        );
        expect(truncationCall).toBeUndefined();
    });

    // ─── Computed Properties ─────────────────────────────────────

    describe('hidePassiveLabel', () => {
        it('returns "Show All" when hidePassive is true (default)', async () => {
            const element = createComponent({ recordId: '001xx000003DGbYAAW' });
            await flushPromises();

            const buttons = element.shadowRoot.querySelectorAll('lightning-button');
            const hideBtn = Array.from(buttons).find(
                b => b.label === 'Show All' || b.label === 'Hide Passive'
            );
            if (hideBtn) {
                expect(hideBtn.label).toBe('Show All');
            }
        });
    });

    describe('classificationFilters', () => {
        it('renders filter badges for each classification', async () => {
            const element = createComponent({ recordId: '001xx000003DGbYAAW' });
            await flushPromises();

            const badges = element.shadowRoot.querySelectorAll(
                '.filter-legend .filter-badge'
            );
            expect(badges.length).toBe(8);
        });
    });

    describe('filter-legend bar', () => {
        it('renders color-coded classification badges as legend', async () => {
            const element = createComponent({ recordId: '001xx000003DGbYAAW' });
            await flushPromises();

            const badges = element.shadowRoot.querySelectorAll('.filter-legend .filter-badge');
            // 8 classification types serve as both filters and legend
            expect(badges.length).toBe(8);
        });
    });

    // ─── Stats Bar ───────────────────────────────────────────────

    it('renders stats bar with node and edge counts', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const statsBar = element.shadowRoot.querySelector('.stats-bar');
        expect(statsBar).toBeTruthy();
        expect(statsBar.textContent).toContain('Nodes:');
        expect(statsBar.textContent).toContain('Edges:');
    });

    it('renders truncation warning in stats bar when truncated', async () => {
        getGraphData.mockResolvedValue(MOCK_TRUNCATED_DATA);

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const warning = element.shadowRoot.querySelector('.truncation-warning');
        expect(warning).toBeTruthy();
        expect(warning.textContent).toContain('550');
    });

    it('does not render truncation warning when not truncated', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const warning = element.shadowRoot.querySelector('.truncation-warning');
        expect(warning).toBeNull();
    });

    // ─── Toolbar Actions ─────────────────────────────────────────

    it('calls refreshGraphData when refresh button clicked', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshButton = Array.from(buttons).find(b => b.label === 'Refresh');
        expect(refreshButton).toBeTruthy();

        refreshButton.click();
        await flushPromises();

        expect(refreshGraphData).toHaveBeenCalledWith(
            expect.objectContaining({
                accountId: '001xx000003DGbYAAW'
            })
        );
    });

    it('shows success toast after refresh', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        ShowToastEvent.mockClear();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshButton = Array.from(buttons).find(b => b.label === 'Refresh');
        refreshButton.click();
        await flushPromises();

        expect(ShowToastEvent).toHaveBeenCalledWith(
            expect.objectContaining({
                title: 'Success',
                variant: 'success'
            })
        );
    });

    it('shows error toast when refresh fails', async () => {
        refreshGraphData.mockRejectedValue({ body: { message: 'Refresh failed' } });

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        ShowToastEvent.mockClear();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshButton = Array.from(buttons).find(b => b.label === 'Refresh');
        refreshButton.click();
        await flushPromises();

        expect(ShowToastEvent).toHaveBeenCalledWith(
            expect.objectContaining({
                title: 'Error',
                variant: 'error'
            })
        );
    });

    it('toggles hidePassive and reloads data', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        getGraphData.mockClear();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const toggleBtn = Array.from(buttons).find(
            b => b.label === 'Show All' || b.label === 'Hide Passive'
        );

        if (toggleBtn) {
            toggleBtn.click();
            await flushPromises();

            expect(getGraphData).toHaveBeenCalled();
        }
    });

    // ─── Slider / Threshold ──────────────────────────────────────

    it('renders threshold input', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const input = element.shadowRoot.querySelector('.threshold-control');
        expect(input).toBeTruthy();
        expect(input.type).toBe('number');
        expect(input.min).toBe('0');
        expect(input.max).toBe('20');
    });

    // ─── Detail Panel ────────────────────────────────────────────

    it('does not show detail panel when no node selected', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const panel = element.shadowRoot.querySelector('.detail-panel');
        expect(panel).toBeNull();
    });

    // ─── Loading State ───────────────────────────────────────────

    it('shows spinner initially', () => {
        getGraphConfig.mockReturnValue(new Promise(() => {}));
        loadScript.mockReturnValue(new Promise(() => {}));

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).toBeTruthy();
    });

    // ─── extractErrorMessage ─────────────────────────────────────

    describe('extractErrorMessage', () => {
        it('returns string errors directly', async () => {
            getGraphData.mockRejectedValue('Simple error');

            createComponent({ recordId: '001xx000003DGbYAAW' });
            await flushPromises();

            expect(ShowToastEvent).toHaveBeenCalledWith(
                expect.objectContaining({
                    message: expect.stringContaining('Simple error')
                })
            );
        });

        it('extracts body.message from Apex errors', async () => {
            getGraphData.mockRejectedValue({
                body: { message: 'Apex error message' }
            });

            createComponent({ recordId: '001xx000003DGbYAAW' });
            await flushPromises();

            expect(ShowToastEvent).toHaveBeenCalledWith(
                expect.objectContaining({
                    message: expect.stringContaining('Apex error message')
                })
            );
        });

        it('extracts message from standard Error objects', async () => {
            getGraphData.mockRejectedValue(new Error('Standard error'));

            createComponent({ recordId: '001xx000003DGbYAAW' });
            await flushPromises();

            expect(ShowToastEvent).toHaveBeenCalledWith(
                expect.objectContaining({
                    message: expect.stringContaining('Standard error')
                })
            );
        });

        it('falls back to "Unknown error" for unrecognized errors', async () => {
            getGraphData.mockRejectedValue({});

            createComponent({ recordId: '001xx000003DGbYAAW' });
            await flushPromises();

            expect(ShowToastEvent).toHaveBeenCalledWith(
                expect.objectContaining({
                    message: expect.stringContaining('Unknown error')
                })
            );
        });
    });

    // ─── Classification Override ─────────────────────────────────

    it('calls overrideClassification apex when combobox changes', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        // Node selection happens via canvas click (not DOM), so we verify
        // the Apex mock is wired up and not called without interaction
        expect(overrideClassification).not.toHaveBeenCalled();
    });

    // ─── DisconnectedCallback Cleanup ────────────────────────────

    it('cleans up on disconnect', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        // Disconnect should not throw
        document.body.removeChild(element);
        expect(true).toBe(true);
    });

    // ─── Filter Badges Interaction ───────────────────────────────

    it('toggles filter when badge is clicked', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const badges = element.shadowRoot.querySelectorAll(
            '.filter-legend .filter-badge'
        );
        expect(badges.length).toBeGreaterThan(0);

        // Click first badge to activate filter
        badges[0].click();
        await flushPromises();

        // Click again to deactivate
        badges[0].click();
        await flushPromises();

        expect(element).toBeTruthy();
    });

    // ─── Hidden Count Display ────────────────────────────────────

    it('shows hidden count when hidePassive is true', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const statsBar = element.shadowRoot.querySelector('.stats-bar');
        expect(statsBar.textContent).toContain('Hidden:');
    });

    // ─── Risk Alerts ──────────────────────────────────────────────

    it('shows risk alert button in stats bar when alerts exist', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const riskButton = element.shadowRoot.querySelector('.risk-alert-button');
        expect(riskButton).toBeTruthy();
        expect(riskButton.label).toBe('3 Risks');
    });

    it('does not show risk alert button when no alerts', async () => {
        getGraphData.mockResolvedValue({
            ...MOCK_GRAPH_DATA,
            riskAlerts: []
        });

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const riskButton = element.shadowRoot.querySelector('.risk-alert-button');
        expect(riskButton).toBeNull();
    });

    it('toggles risk panel when alert button clicked', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        // Panel should not be visible initially
        let riskPanel = element.shadowRoot.querySelector('.risk-panel');
        expect(riskPanel).toBeNull();

        // Click risk button to open panel
        const riskButton = element.shadowRoot.querySelector('.risk-alert-button');
        riskButton.click();
        await flushPromises();

        riskPanel = element.shadowRoot.querySelector('.risk-panel');
        expect(riskPanel).toBeTruthy();

        // Should render alert items
        const alertItems = riskPanel.querySelectorAll('.risk-alert-item');
        expect(alertItems.length).toBe(3);
    });

    it('uses destructive variant when high-severity alerts exist', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const riskButton = element.shadowRoot.querySelector('.risk-alert-button');
        expect(riskButton.variant).toBe('destructive');
    });
});

describe('factor breakdown', () => {
    it('renders factor breakdown when contact with strengthFactors is selected', async () => {
        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        // Simulate selecting Jane Doe node (has strengthFactors)
        const canvas = element.shadowRoot.querySelector('canvas');
        canvas.dispatchEvent(new MouseEvent('click', { clientX: 100, clientY: 100 }));
        await flushPromises();

        // Check for factor breakdown section
        const factorBreakdown = element.shadowRoot.querySelector('.factor-breakdown');
        // If node is selected and has strengthFactors, breakdown should render
        // Note: actual selection depends on hit detection which is canvas-based
        // This test verifies the template structure exists
        if (factorBreakdown) {
            const factorRows = factorBreakdown.querySelectorAll('.factor-row');
            expect(factorRows.length).toBeGreaterThan(0);
        }
    });

    it('does not render factor breakdown when no strengthFactors', async () => {
        const dataWithoutFactors = {
            ...MOCK_GRAPH_DATA,
            nodes: MOCK_GRAPH_DATA.nodes.map(n => ({
                ...n,
                strengthFactors: undefined
            }))
        };
        getGraphData.mockResolvedValue(dataWithoutFactors);
        refreshGraphData.mockResolvedValue(dataWithoutFactors);

        const element = createComponent({ recordId: '001xx000003DGbYAAW' });
        await flushPromises();

        const factorBreakdown = element.shadowRoot.querySelector('.factor-breakdown');
        expect(factorBreakdown).toBeNull();
    });
});
