/**
 * ATOMICA Landing Page Interactive Scripts
 *
 * Handles:
 *   1. Smooth scroll for anchor links
 *   2. Scroll-reveal animations (Intersection Observer)
 *   3. Mobile hamburger menu
 *   4. [data-launch-demo] — scroll to #download, open HTML5 accordion item,
 *      then open the first demo module (with OpenFL lazy-load)
 *   5. Download accordion — multi-open policy (Windows/Linux/Android/HTML5)
 *   6. Nested demo accordion (inside HTML5 item) — single-open policy,
 *      lazy-loads OpenFL runtime via lime.embed()
 *
 * Changelog:
 * [2026-09-05] v1.3.1 - FIXED: querySelectorAll selector was corrupted
 *                        ('aref^="#"]' → 'a[href^="#"]'). This single typo
 *                        threw DOMException at script load, killing every
 *                        event handler below it.
 * [2026-09-04] v1.3.0 - Demo modules nested inside HTML5 download accordion item
 *                      - Added [data-launch-demo] button trigger
 *                      - Demo accordion is now nested; uses .nested-accordion scope
 * [2026-09-04] v1.2.0 - Merged demo.html accordion into index.html
 *                      - Added download accordion handler
 *                      - Removed language switcher (EN-only)
 * [2026-08-11] v1.1.0 - Fixed hero animation hang; visibility check on init
 * [2026-08-11] v1.0.0 - Initial creation of main.js with core interactions.
 */

document.addEventListener('DOMContentLoaded', () => {

    // ====================================================================
    // 1. SMOOTH SCROLL FOR ANCHOR LINKS
    // ====================================================================
    // [data-launch-demo] buttons get special handling in section 4 below;
    // regular anchors just smooth-scroll to the target.
    document.querySelectorAll('a[href^="#"]:not([data-launch-demo])').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const targetId = this.getAttribute('href');
            if (targetId === '#' || targetId.length < 2) return;
            const targetElement = document.querySelector(targetId);
            if (targetElement) {
                e.preventDefault();
                targetElement.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });

    // ====================================================================
    // 2. SCROLL-REVEAL ANIMATIONS (Intersection Observer)
    // ====================================================================
    const animatedElements = document.querySelectorAll('[data-animate]');
    const observerOptions = { root: null, rootMargin: '0px', threshold: 0.1 };

    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const delay = entry.target.getAttribute('data-delay') || 0;
                setTimeout(() => { entry.target.classList.add('is-visible'); }, parseInt(delay));
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    animatedElements.forEach(el => {
        const rect = el.getBoundingClientRect();
        const windowHeight = window.innerHeight || document.documentElement.clientHeight;
        if (rect.top < windowHeight && rect.bottom > 0) {
            const delay = el.getAttribute('data-delay') || 0;
            setTimeout(() => { el.classList.add('is-visible'); }, parseInt(delay));
        } else {
            observer.observe(el);
        }
    });

    // ====================================================================
    // 3. MOBILE HAMBURGER MENU
    // ====================================================================
    const menuToggle = document.querySelector('.menu-toggle');
    const navMenu = document.querySelector('.nav-menu');
    if (menuToggle && navMenu) {
        menuToggle.addEventListener('click', () => {
            const isActive = navMenu.classList.toggle('is-active');
            menuToggle.setAttribute('aria-expanded', isActive);
        });
    }

    // ====================================================================
    // 4. [data-launch-demo] — "Launch Demonstration" button
    // ====================================================================
    // Flow:
    //   1. Smooth-scroll to the #download section
    //   2. After scroll settles (~650ms), open the HTML5 download accordion item
    //   3. After the HTML5 accordion expands (~700ms), open the first nested
    //      demo module and lazy-load the OpenFL runtime
    // If HTML5 or the first demo is already open, we leave it alone — the user
    // may have already configured a different view they want to keep.
    const launchDemoButtons = document.querySelectorAll('[data-launch-demo]');
    launchDemoButtons.forEach(btn => {
        btn.addEventListener('click', function (e) {
            e.preventDefault();
            const downloadSection = document.querySelector('#download');
            if (!downloadSection) return;

            downloadSection.scrollIntoView({ behavior: 'smooth', block: 'start' });

            setTimeout(function () {
                // Step 2: open the HTML5 download accordion item
                const html5Header = document.querySelector('.accordion-header[data-download-id="html5"]');
                if (!html5Header) return;
                const html5Item = html5Header.closest('.accordion-item');
                if (!html5Item) return;

                if (!html5Item.classList.contains('is-active')) {
                    html5Header.click();   // triggers the download-accordion handler (section 5)
                }

                // Step 3: open the first demo module after HTML5 has expanded
                setTimeout(function () {
                    const firstDemoHeader = document.querySelector(
                        '.nested-accordion .accordion-header[data-demo-id="1"]'
                    );
                    if (!firstDemoHeader) return;
                    const firstDemoItem = firstDemoHeader.closest('.accordion-item');
                    if (!firstDemoItem) return;

                    if (!firstDemoItem.classList.contains('is-active')) {
                        firstDemoHeader.click();   // triggers the demo-accordion handler (section 6)
                    }
                }, 700);   // wait for HTML5 content transition (0.45s) + safety
            }, 650);       // wait for smooth-scroll to settle
        });
    });

    // ====================================================================
    // 5. DOWNLOAD ACCORDION (multi-open policy)
    // ====================================================================
    // Each platform card (Windows / Linux / Android / HTML5) opens and closes
    // independently. Multiple can be open at once — they are documentation,
    // not exclusive. The HTML5 item is special: its content contains the
    // nested demo accordion (handled in section 6).
    const downloadHeaders = document.querySelectorAll('.accordion-header[data-download-id]');
    downloadHeaders.forEach(header => {
        header.addEventListener('click', function () {
            const item = header.closest('.accordion-item');
            if (!item) return;
            const wasActive = item.classList.contains('is-active');
            item.classList.toggle('is-active');
            header.setAttribute('aria-expanded', wasActive ? 'false' : 'true');
        });
    });

    // ====================================================================
    // 6. NESTED DEMO ACCORDION (inside HTML5 item) — single-open policy
    // ====================================================================
    // Only one demo module can be open at a time inside the HTML5 item.
    // Opening another closes the rest. First open of a module lazy-loads
    // the OpenFL runtime via lime.embed() into the runtime-container canvas.
    const demoHeaders = document.querySelectorAll('.nested-accordion .accordion-header[data-demo-id]');

    demoHeaders.forEach(header => {
        header.addEventListener('click', function () {
            const item = header.closest('.accordion-item');
            if (!item) return;
            const wasActive = item.classList.contains('is-active');

            // Close ALL sibling demo items (single-open within the nested-accordion)
            const nestedContainer = item.closest('.nested-accordion');
            if (nestedContainer) {
                nestedContainer.querySelectorAll('.accordion-item').forEach(other => {
                    other.classList.remove('is-active');
                    const h = other.querySelector('.accordion-header');
                    if (h) h.setAttribute('aria-expanded', 'false');
                });
            }

            // Open the clicked one (if it was closed)
            if (!wasActive) {
                item.classList.add('is-active');
                header.setAttribute('aria-expanded', 'true');

                // Smooth-scroll to the demo header after the CSS animation settles.
                // The HTML5 parent may have just expanded, so the layout is still
                // shifting; we wait for both transitions to complete.
                setTimeout(function () {
                    header.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }, 550);

                // Lazy-load the OpenFL runtime on first open
                const runtimeContainer = item.querySelector('.runtime-container');
                const demoId = header.getAttribute('data-demo-id');

                if (
                    runtimeContainer &&
                    runtimeContainer.getAttribute('data-initialized') === 'false' &&
                    typeof lime !== 'undefined' &&
                    typeof lime.embed === 'function'
                ) {
                    runtimeContainer.setAttribute('data-pending', 'true');

                    // Wait 600ms for the CSS flex-grow animation to settle
                    // so clientWidth / clientHeight are correct.
                    setTimeout(function () {
                        console.log('[ALTAURI] Initializing Runtime for Demo ' + demoId + '...');

                        const targetWidth  = runtimeContainer.clientWidth;
                        const targetHeight = runtimeContainer.clientHeight;

                        lime.embed('ALTAURI_Web', 'demo-runtime-' + demoId, targetWidth, targetHeight);

                        // Capture mouse events on the canvas so the page
                        // doesn't scroll weirdly while the user interacts.
                        const canvas = runtimeContainer.querySelector('canvas');
                        if (canvas) {
                            canvas.addEventListener('wheel', function (e) {
                                e.preventDefault();
                                e.stopPropagation();
                            }, { passive: false });

                            canvas.addEventListener('mousedown', function (e) {
                                if (e.button === 1) {
                                    e.preventDefault();
                                    e.stopPropagation();
                                }
                            }, { passive: false });

                            canvas.addEventListener('auxclick', function (e) {
                                if (e.button === 1) {
                                    e.preventDefault();
                                    e.stopPropagation();
                                }
                            }, { passive: false });
                        }

                        runtimeContainer.setAttribute('data-initialized', 'true');
                        runtimeContainer.removeAttribute('data-pending');
                    }, 600);
                }
            }
        });
    });

    console.log('ATOMICA Interactive Runtime Initialized.');
});
