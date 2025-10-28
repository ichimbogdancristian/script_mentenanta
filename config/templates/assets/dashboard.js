/**
 * Windows Maintenance Report - Interactive Dashboard JavaScript
 * Version: 4.0
 * 
 * Provides interactive functionality for the modern dashboard including:
 * - Theme switching (light/dark mode)
 * - Module filtering and searching
 * - Collapsible sections
 * - Scroll progress tracking
 * - Export functionality
 * - Responsive navigation
 */

// Global state management
const Dashboard = {
    currentTheme: 'light',
    isFullscreen: false,
    modules: [],
    filteredModules: [],
    searchTerm: '',
    statusFilter: 'all',

    // Initialize dashboard functionality
    init() {
        this.setupEventListeners();
        this.loadTheme();
        this.setupScrollProgress();
        this.setupBackToTop();
        this.setupSearch();
        this.setupFilters();
        this.setupKeyboardShortcuts();
        this.loadModules();
        this.animateOnLoad();

        console.log('Dashboard initialized successfully');
    },

    // Set up all event listeners
    setupEventListeners() {
        // Theme toggle
        const themeToggle = document.getElementById('themeToggle');
        if (themeToggle) {
            themeToggle.addEventListener('click', () => this.toggleTheme());
        }

        // Search functionality
        const searchInput = document.getElementById('module-search');
        if (searchInput) {
            searchInput.addEventListener('input', (e) => this.handleSearch(e.target.value));
            searchInput.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    e.target.value = '';
                    this.handleSearch('');
                }
            });
        }

        // Status filter
        const statusFilter = document.getElementById('status-filter');
        if (statusFilter) {
            statusFilter.addEventListener('change', (e) => this.handleStatusFilter(e.target.value));
        }

        // Smooth scrolling for navigation links
        document.querySelectorAll('a[href^="#"]').forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const targetId = link.getAttribute('href').substring(1);
                this.scrollToSection(targetId);
            });
        });

        // Handle window resize
        window.addEventListener('resize', () => this.handleResize());

        // Handle scroll events
        window.addEventListener('scroll', () => {
            this.updateScrollProgress();
            this.updateBackToTopVisibility();
            this.updateActiveNavigation();
        });
    },

    // Theme management
    loadTheme() {
        const savedTheme = localStorage.getItem('dashboard-theme') || 'light';
        this.setTheme(savedTheme);
    },

    toggleTheme() {
        const newTheme = this.currentTheme === 'light' ? 'dark' : 'light';
        this.setTheme(newTheme);
    },

    setTheme(theme) {
        this.currentTheme = theme;
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem('dashboard-theme', theme);

        // Update theme toggle button
        const themeIcon = document.getElementById('themeIcon');
        const themeText = document.getElementById('themeText');
        const themeToggle = document.getElementById('themeToggle');

        if (themeIcon && themeText && themeToggle) {
            if (theme === 'dark') {
                themeIcon.textContent = '☀️';
                themeText.textContent = 'Light Mode';
                themeToggle.setAttribute('aria-pressed', 'true');
            } else {
                themeIcon.textContent = '🌙';
                themeText.textContent = 'Dark Mode';
                themeToggle.setAttribute('aria-pressed', 'false');
            }
        }

        // Announce theme change for screen readers
        this.announceToScreenReader(`Switched to ${theme} mode`);
    },

    // Scroll progress indicator
    setupScrollProgress() {
        this.progressBar = document.getElementById('scroll-progress');
    },

    updateScrollProgress() {
        if (!this.progressBar) return;

        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const scrollHeight = document.documentElement.scrollHeight - window.innerHeight;
        const progress = (scrollTop / scrollHeight) * 100;

        this.progressBar.style.width = `${Math.min(progress, 100)}%`;
    },

    // Back to top functionality
    setupBackToTop() {
        this.backToTopButton = document.getElementById('back-to-top');
        if (this.backToTopButton) {
            this.backToTopButton.addEventListener('click', () => this.scrollToTop());
        }
    },

    updateBackToTopVisibility() {
        if (!this.backToTopButton) return;

        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const shouldShow = scrollTop > 300;

        this.backToTopButton.classList.toggle('visible', shouldShow);
    },

    scrollToTop() {
        window.scrollTo({
            top: 0,
            behavior: 'smooth'
        });

        // Focus on the skip link for accessibility
        const skipLink = document.querySelector('a[href="#main-content"]');
        if (skipLink) {
            skipLink.focus();
        }
    },

    // Navigation and scrolling
    scrollToSection(sectionId) {
        const section = document.getElementById(sectionId);
        if (section) {
            const headerOffset = 80; // Account for sticky header
            const elementPosition = section.getBoundingClientRect().top;
            const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

            window.scrollTo({
                top: offsetPosition,
                behavior: 'smooth'
            });

            // Update URL without triggering scroll
            history.replaceState(null, null, `#${sectionId}`);

            // Announce navigation for screen readers
            this.announceToScreenReader(`Navigated to ${section.textContent || sectionId} section`);
        }
    },

    updateActiveNavigation() {
        const sections = document.querySelectorAll('section[id]');
        const navLinks = document.querySelectorAll('.nav-link');

        let currentSection = '';

        sections.forEach(section => {
            const sectionTop = section.getBoundingClientRect().top;
            if (sectionTop <= 100 && sectionTop > -section.offsetHeight + 100) {
                currentSection = section.id;
            }
        });

        navLinks.forEach(link => {
            const href = link.getAttribute('href');
            if (href === `#${currentSection}`) {
                link.classList.add('active');
            } else {
                link.classList.remove('active');
            }
        });
    },

    // Search and filtering
    setupSearch() {
        this.searchInput = document.getElementById('module-search');
    },

    setupFilters() {
        this.statusFilterSelect = document.getElementById('status-filter');
    },

    handleSearch(searchTerm) {
        this.searchTerm = searchTerm.toLowerCase().trim();
        this.filterModules();

        // Update search input state
        if (this.searchInput) {
            this.searchInput.classList.toggle('has-value', this.searchTerm.length > 0);
        }
    },

    handleStatusFilter(status) {
        this.statusFilter = status;
        this.filterModules();
    },

    filterModules() {
        const moduleCards = document.querySelectorAll('.module-card');
        const noModulesMessage = document.getElementById('no-modules-message');
        let visibleCount = 0;

        moduleCards.forEach(card => {
            const moduleName = card.dataset.module || '';
            const moduleStatus = card.dataset.status || '';
            const cardText = card.textContent.toLowerCase();

            // Check search term match
            const searchMatch = !this.searchTerm ||
                moduleName.toLowerCase().includes(this.searchTerm) ||
                cardText.includes(this.searchTerm);

            // Check status filter match
            const statusMatch = this.statusFilter === 'all' || moduleStatus === this.statusFilter;

            const shouldShow = searchMatch && statusMatch;

            if (shouldShow) {
                card.style.display = 'block';
                card.style.animation = 'fadeIn 0.3s ease-out';
                visibleCount++;
            } else {
                card.style.display = 'none';
            }
        });

        // Show/hide "no modules" message
        if (noModulesMessage) {
            noModulesMessage.classList.toggle('hidden', visibleCount > 0);
        }

        // Update results count
        this.updateResultsCount(visibleCount, moduleCards.length);
    },

    updateResultsCount(visible, total) {
        let countText = `Showing ${visible} of ${total} modules`;

        if (this.searchTerm) {
            countText += ` matching "${this.searchTerm}"`;
        }

        if (this.statusFilter !== 'all') {
            countText += ` with status "${this.statusFilter}"`;
        }

        // Update or create results counter
        let counter = document.getElementById('results-counter');
        if (!counter) {
            counter = document.createElement('div');
            counter.id = 'results-counter';
            counter.className = 'text-sm text-gray-600 mb-4';

            const modulesContainer = document.getElementById('modules-container');
            if (modulesContainer) {
                modulesContainer.parentNode.insertBefore(counter, modulesContainer);
            }
        }

        counter.textContent = countText;
        counter.style.display = (this.searchTerm || this.statusFilter !== 'all') ? 'block' : 'none';
    },

    clearFilters() {
        this.searchTerm = '';
        this.statusFilter = 'all';

        if (this.searchInput) {
            this.searchInput.value = '';
            this.searchInput.classList.remove('has-value');
        }

        if (this.statusFilterSelect) {
            this.statusFilterSelect.value = 'all';
        }

        this.filterModules();

        // Announce filter clear for screen readers
        this.announceToScreenReader('Filters cleared, showing all modules');
    },

    // Module management
    loadModules() {
        this.modules = Array.from(document.querySelectorAll('.module-card')).map(card => ({
            element: card,
            name: card.dataset.module || '',
            status: card.dataset.status || '',
            text: card.textContent.toLowerCase()
        }));

        this.filteredModules = [...this.modules];
    },

    // Export functionality
    exportToJSON() {
        const reportData = this.gatherReportData();
        const dataStr = JSON.stringify(reportData, null, 2);
        const dataBlob = new Blob([dataStr], { type: 'application/json' });

        const link = document.createElement('a');
        link.href = URL.createObjectURL(dataBlob);
        link.download = `maintenance-report-${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);

        this.showToast('Report exported successfully!', 'success');
    },

    gatherReportData() {
        // Gather all report data for export
        const data = {
            metadata: {
                generatedAt: new Date().toISOString(),
                userAgent: navigator.userAgent,
                reportVersion: '4.0'
            },
            summary: this.extractSummaryData(),
            modules: this.extractModuleData(),
            systemInfo: this.extractSystemInfo(),
            timestamp: Date.now()
        };

        return data;
    },

    extractSummaryData() {
        const metrics = {};
        document.querySelectorAll('.metric-card').forEach(card => {
            const label = card.querySelector('.metric-label')?.textContent;
            const value = card.querySelector('.metric-value')?.textContent;
            if (label && value) {
                metrics[label] = value;
            }
        });
        return metrics;
    },

    extractModuleData() {
        return this.modules.map(module => ({
            name: module.name,
            status: module.status,
            visible: module.element.style.display !== 'none'
        }));
    },

    extractSystemInfo() {
        const systemInfo = {};
        document.querySelectorAll('.metadata-item').forEach(item => {
            const label = item.querySelector('.metadata-label')?.textContent;
            const value = item.querySelector('.metadata-value')?.textContent;
            if (label && value) {
                systemInfo[label] = value;
            }
        });
        return systemInfo;
    },

    // Print functionality
    printReport() {
        // Optimize for printing
        document.body.classList.add('printing');

        // Hide interactive elements
        const controlElements = document.querySelectorAll('.top-controls-bar, .back-to-top, .control-btn');
        controlElements.forEach(el => el.style.display = 'none');

        // Expand all modules for complete print
        document.querySelectorAll('.module-body').forEach(body => {
            body.style.display = 'block';
            body.classList.add('expanded');
        });

        // Trigger print
        window.print();

        // Restore after print
        setTimeout(() => {
            document.body.classList.remove('printing');
            controlElements.forEach(el => el.style.display = '');

            // Restore module states
            document.querySelectorAll('.module-body').forEach(body => {
                if (!body.classList.contains('user-expanded')) {
                    body.style.display = 'none';
                    body.classList.remove('expanded');
                }
            });
        }, 1000);

        this.showToast('Report sent to printer', 'info');
    },

    // Fullscreen functionality
    toggleFullscreen() {
        if (!document.fullscreenElement) {
            document.documentElement.requestFullscreen().then(() => {
                this.isFullscreen = true;
                this.updateFullscreenButton();
            }).catch(err => {
                console.warn('Error attempting to enable fullscreen:', err);
            });
        } else {
            document.exitFullscreen().then(() => {
                this.isFullscreen = false;
                this.updateFullscreenButton();
            });
        }
    },

    updateFullscreenButton() {
        const button = document.querySelector('[onclick="toggleFullscreen()"]');
        if (button) {
            const icon = button.querySelector('.btn-icon');
            const text = button.querySelector('.btn-text');

            if (this.isFullscreen) {
                if (icon) icon.textContent = '🔲';
                if (text) text.textContent = 'Exit Fullscreen';
            } else {
                if (icon) icon.textContent = '🔳';
                if (text) text.textContent = 'Fullscreen';
            }
        }
    },

    // Keyboard shortcuts
    setupKeyboardShortcuts() {
        document.addEventListener('keydown', (e) => {
            // Only process shortcuts when not typing in inputs
            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

            switch (e.key) {
                case '/':
                    e.preventDefault();
                    this.focusSearch();
                    break;
                case 'Escape':
                    this.clearFilters();
                    break;
                case 't':
                    if (e.ctrlKey || e.metaKey) {
                        e.preventDefault();
                        this.toggleTheme();
                    }
                    break;
                case 'p':
                    if (e.ctrlKey || e.metaKey) {
                        e.preventDefault();
                        this.printReport();
                    }
                    break;
                case 'f':
                    if (e.ctrlKey || e.metaKey) {
                        e.preventDefault();
                        this.focusSearch();
                    }
                    break;
                case 'Home':
                    e.preventDefault();
                    this.scrollToTop();
                    break;
            }
        });
    },

    focusSearch() {
        if (this.searchInput) {
            this.searchInput.focus();
            this.searchInput.select();
        }
    },

    // Responsive handling
    handleResize() {
        // Update layout for responsive design
        const isMobile = window.innerWidth < 768;

        // Adjust module card layouts for mobile
        document.querySelectorAll('.module-card').forEach(card => {
            card.classList.toggle('mobile-layout', isMobile);
        });

        // Update navigation for mobile
        const headerNav = document.querySelector('.header-nav');
        if (headerNav) {
            headerNav.classList.toggle('mobile-nav', isMobile);
        }
    },

    // Animation and visual effects
    animateOnLoad() {
        // Animate metric cards with stagger
        const metricCards = document.querySelectorAll('.metric-card');
        metricCards.forEach((card, index) => {
            card.style.animationDelay = `${index * 0.1}s`;
            card.classList.add('animate-fade-in');
        });

        // Animate progress bars
        setTimeout(() => {
            document.querySelectorAll('.progress-fill').forEach(bar => {
                const width = bar.style.width;
                bar.style.width = '0%';
                setTimeout(() => {
                    bar.style.width = width;
                }, 100);
            });
        }, 500);

        // Animate module cards
        const moduleCards = document.querySelectorAll('.module-card');
        moduleCards.forEach((card, index) => {
            card.style.animationDelay = `${(index * 0.05) + 0.5}s`;
            card.classList.add('animate-fade-in');
        });
    },

    // Utility functions
    showToast(message, type = 'info', duration = 3000) {
        // Remove existing toasts
        document.querySelectorAll('.toast').forEach(toast => toast.remove());

        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;

        const icon = this.getToastIcon(type);
        toast.innerHTML = `
            <span class="toast-icon">${icon}</span>
            <span class="toast-message">${message}</span>
        `;

        toast.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: var(--${type === 'success' ? 'success' : type === 'error' ? 'error' : 'info'}-500);
            color: white;
            padding: 12px 16px;
            border-radius: 8px;
            box-shadow: var(--shadow-lg);
            z-index: 10000;
            display: flex;
            align-items: center;
            gap: 8px;
            max-width: 400px;
            animation: slideInRight 0.3s ease-out;
            font-size: 14px;
            font-weight: 500;
        `;

        document.body.appendChild(toast);

        // Auto-remove after duration
        setTimeout(() => {
            toast.style.animation = 'slideOutRight 0.3s ease-in forwards';
            setTimeout(() => {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 300);
        }, duration);

        // Click to dismiss
        toast.addEventListener('click', () => {
            toast.style.animation = 'slideOutRight 0.3s ease-in forwards';
            setTimeout(() => {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 300);
        });
    },

    getToastIcon(type) {
        const icons = {
            success: '✅',
            error: '❌',
            warning: '⚠️',
            info: 'ℹ️'
        };
        return icons[type] || icons.info;
    },

    announceToScreenReader(message) {
        // Create a live region for screen reader announcements
        let liveRegion = document.getElementById('sr-live-region');
        if (!liveRegion) {
            liveRegion = document.createElement('div');
            liveRegion.id = 'sr-live-region';
            liveRegion.setAttribute('aria-live', 'polite');
            liveRegion.setAttribute('aria-atomic', 'true');
            liveRegion.className = 'sr-only';
            document.body.appendChild(liveRegion);
        }

        liveRegion.textContent = message;

        // Clear after announcement
        setTimeout(() => {
            liveRegion.textContent = '';
        }, 1000);
    },

    // Additional utility functions
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }
};

// Global functions for template compatibility
function toggleTheme() {
    Dashboard.toggleTheme();
}

function printReport() {
    Dashboard.printReport();
}

function exportToJSON() {
    Dashboard.exportToJSON();
}

function toggleFullscreen() {
    Dashboard.toggleFullscreen();
}

function scrollToTop() {
    Dashboard.scrollToTop();
}

function scrollToSection(sectionId) {
    Dashboard.scrollToSection(sectionId);
}

function filterModules(status) {
    Dashboard.handleStatusFilter(status);
}

function clearFilters() {
    Dashboard.clearFilters();
}

// Module-specific functions
function toggleModuleDetails(moduleId) {
    const body = document.getElementById(`module-body-${moduleId}`);
    const icon = document.getElementById(`expand-icon-${moduleId}`);

    if (body && icon) {
        const isExpanded = body.classList.contains('expanded');

        if (isExpanded) {
            body.classList.remove('expanded', 'user-expanded');
            body.style.display = 'none';
            icon.textContent = '▶';
            icon.classList.remove('expanded');
        } else {
            body.style.display = 'block';
            body.classList.add('expanded', 'user-expanded');
            icon.textContent = '▼';
            icon.classList.add('expanded');
        }

        // Announce state change
        const moduleName = body.closest('.module-card')?.dataset.module || 'module';
        Dashboard.announceToScreenReader(`${moduleName} details ${isExpanded ? 'collapsed' : 'expanded'}`);
    }
}

// Log and download functions
function viewLog(logPath) {
    Dashboard.showToast(`Opening log: ${logPath}`, 'info');
    // In a real implementation, this would open the log file
    console.log('View log:', logPath);
}

function downloadLog(logPath) {
    Dashboard.showToast(`Downloading log: ${logPath}`, 'info');
    // In a real implementation, this would download the log file
    console.log('Download log:', logPath);
}

function downloadAllLogs() {
    Dashboard.showToast('Preparing log download...', 'info');
    // In a real implementation, this would create a zip of all logs
    console.log('Download all logs');
}

// Additional interactive functions
function scheduleNextMaintenance() {
    Dashboard.showToast('Maintenance scheduling feature coming soon!', 'info');
}

function shareFeedback() {
    Dashboard.showToast('Feedback form would open here', 'info');
}

function exportReport() {
    Dashboard.exportToJSON();
}

// Initialize dashboard when DOM is ready
function initializeDashboard() {
    Dashboard.init();
}

// Add required CSS for animations if not already present
if (!document.getElementById('dashboard-animations')) {
    const animationStyles = document.createElement('style');
    animationStyles.id = 'dashboard-animations';
    animationStyles.textContent = `
        @keyframes slideInRight {
            from { transform: translateX(100%); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        @keyframes slideOutRight {
            from { transform: translateX(0); opacity: 1; }
            to { transform: translateX(100%); opacity: 0; }
        }
        .search-input.has-value {
            border-color: var(--primary-500);
            box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
        }
        .mobile-layout .module-stats {
            flex-direction: column;
            gap: var(--space-2);
        }
        .mobile-nav {
            flex-direction: column;
            gap: var(--space-2);
        }
        .mobile-nav .nav-link {
            flex: 1;
            text-align: center;
        }
        .printing .control-btn,
        .printing .top-controls-bar,
        .printing .back-to-top {
            display: none !important;
        }
    `;
    document.head.appendChild(animationStyles);
}

// Export Dashboard object for advanced usage
window.MaintenanceDashboard = Dashboard;