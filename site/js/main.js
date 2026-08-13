/**
 * ATOMICA Landing Page Interactive Scripts
 * Описание: Плавный скролл, анимации появления блоков (Intersection Observer), 
 * мобильное меню и базовая валидация форм.
 * 
 * Changelog:
 * [2026-08-11] v1.1.0 - Исправлена проблема с зависающей анимацией hero-секции
 *                        Добавлена проверка видимости элементов при инициализации
 * [2026-08-11] v1.0.0 - Initial creation of main.js with core interactions.
 */

document.addEventListener('DOMContentLoaded', () => {
    
    // 1. Плавный скролл для якорных ссылок
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const targetId = this.getAttribute('href');
            if (targetId === '#') return;
            const targetElement = document.querySelector(targetId);
            if (targetElement) {
                targetElement.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });

    // 2. Анимации появления блоков при скролле (Intersection Observer)
    const animatedElements = document.querySelectorAll('[data-animate]');
    
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const delay = entry.target.getAttribute('data-delay') || 0;
                setTimeout(() => {
                    entry.target.classList.add('is-visible');
                }, parseInt(delay));
                observer.unobserve(entry.target); // Анимируем только один раз
            }
        });
    }, observerOptions);

    // КРИТИЧНО: Проверяем элементы, которые уже видны при загрузке страницы
    animatedElements.forEach(el => {
        const rect = el.getBoundingClientRect();
        const windowHeight = window.innerHeight || document.documentElement.clientHeight;
        
        // Если элемент уже в viewport при загрузке — сразу делаем видимым
        if (rect.top < windowHeight && rect.bottom > 0) {
            const delay = el.getAttribute('data-delay') || 0;
            setTimeout(() => {
                el.classList.add('is-visible');
            }, parseInt(delay));
        } else {
            // Иначе наблюдаем через IntersectionObserver
            observer.observe(el);
        }
    });

    // 3. Мобильное меню (Hamburger)
    const menuToggle = document.querySelector('.menu-toggle');
    const navMenu = document.querySelector('.nav-menu');
    
    if (menuToggle && navMenu) {
        menuToggle.addEventListener('click', () => {
            const isActive = navMenu.classList.toggle('is-active');
            menuToggle.setAttribute('aria-expanded', isActive);
        });
    }

    console.log('ATOMICA Interactive Runtime Initialized.');
});