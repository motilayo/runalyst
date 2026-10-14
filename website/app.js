/**
 * RUNALYST — Apple Promo Page Interactive Logic
 * Domain: runalyst.ca
 */

document.addEventListener('DOMContentLoaded', () => {
  initScreenshotShowcase();
  initVideoPlayback();
  initMobileMenu();
  initScrollAnimations();
  initScrollSpy();
});

/* ==========================================================================
   2. Interactive Screenshot Showcase (Tabs & Cards)
   ========================================================================== */
function initScreenshotShowcase() {
  const tabs = document.querySelectorAll('.tab-pill, .showcase-pill-btn, .showcase-tab, .tab-btn');
  const img = document.getElementById('showcase-main-img');
  const title = document.getElementById('showcase-title');
  const badge = document.getElementById('showcase-badge');
  const desc = document.getElementById('showcase-desc');
  const bullet1 = document.getElementById('showcase-b1');
  const bullet2 = document.getElementById('showcase-b2');
  const bullet3 = document.getElementById('showcase-b3');

  const cardData = {
    biometrics: {
      src: 'assets/images/01_Intelligent_Biometrics.png',
      badge: '01 / RAW RUNNING TELEMETRY',
      title: 'Intelligent Running Biometrics',
      desc: 'Ditch static vanity metrics. Runalyst extracts live cadence deltas, vertical oscillation, and ground contact balance from Apple Watch and benchmarks them against your rolling 30-day relative baseline.',
      b1: 'Zero arbitrary targets: evaluated strictly against your personal physiology',
      b2: 'Sub-second cadence delta tracking against your 30-day average',
      b3: 'Working stats engine that automatically trims dead-stop traffic pauses'
    },
    coaching: {
      src: 'assets/images/02_AI_Coaching.png',
      badge: '02 / ON-DEVICE FOUNDATION MODELS',
      title: 'On-Device AI Coaching Engine',
      desc: 'Powered natively by Apple FoundationModels running strictly on Apple Silicon. Get conversational, highly tailored feedback after every run with zero latency and zero cloud tracking.',
      b1: 'Mathematical determinism: Swift evaluates physiological rules before prompting',
      b2: 'Actionable observations grouped into Cardio, Form, and Pacing',
      b3: '100% on-device inference: private, instant, and works completely offline'
    },
    drills: {
      src: 'assets/images/03_Targeted_Drills.png',
      badge: '03 / PRE-RUN DRILL BREAKDOWN',
      title: 'Targeted Form Drills & Mental Preparation',
      desc: 'Never guess what warm-up to run. When low cadence or fatigue is detected, Runalyst prescribes targeted drills with proportional phase timelines and an interstitial mental preparation readout before syncing to Apple Watch.',
      b1: 'Structured 5-point mental readout: Target Cues, Biomechanical Focus, Phase Breakdown, Strategy, Effort',
      b2: 'Proportional horizontal geometry blocks visualizing warmups, surges, and recovery intervals',
      b3: 'Dynamic duration scaling (5m, 10m, 15m) with one-tap export to Apple Watch WorkoutKit'
    },
    biomechanics: {
      src: 'assets/images/04_Biomechanical_Analysis.png',
      badge: '04 / KINEMATIC FOOT-STRIKE & BOUNCE',
      title: 'Biomechanical Form & Overstride Analysis',
      desc: 'Overstriding acts as an invisible brake on every stride. Runalyst inspects ground contact duration, vertical oscillation, and vertical ratio from your Apple Watch to identify high-impact braking forces before they cause injury.',
      b1: 'Kinematic checklist: center-of-mass landing, knee spring absorption, and vertical bounce',
      b2: 'Actionable real-time alerts when vertical bounce exceeds 10 cm or ground contact exceeds 260 ms',
      b3: 'Targeted form cues: quick step frequency, soft foot landing, and forward pelvis drive'
    },
    catalog: {
      src: 'assets/images/05_PreRun_Library.png',
      badge: '05 / CURATED PRE-RUN DRILL CATALOG',
      title: 'Curated Pre-Run Drills Library',
      desc: 'Browse a complete library of biomechanically targeted primers—from Form Primers and Cadence Pyramids to Aerobic Flushes. Adjust drill duration (5, 10, 15, or 30 mins) with one tap.',
      b1: '10+ structured drill archetypes covering foundation, tempo surges, hills, and recovery',
      b2: 'Live haptic feedback toggle for wrist vibration cues on interval transitions',
      b3: 'Seamless one-tap push to Apple Watch WorkoutKit for guided wrist workouts'
    },
    progression: {
      src: 'assets/images/06_Longitudinal_Progression.png',
      badge: '06 / EFFICIENCY FACTOR & METRICS',
      title: 'Longitudinal Progression',
      desc: 'Watch your running economy evolve over weeks and months. Interactive charts reveal whether your aerobic pace is accelerating while your cardiac cost and vertical oscillation trend lower.',
      b1: 'Efficiency Factor (Pace-to-Heart Rate ratio) tracking over time',
      b2: 'Longitudinal cadence trendlines across steady runs, tempos, and intervals',
      b3: 'Automatic classification into Steady Effort, Progression, Intervals, or Recovery'
    },
    privacy: {
      src: 'assets/images/07_HealthKit_Privacy.png',
      badge: '07 / ZERO-TRACKING MANIFESTO',
      title: '100% Private & HealthKit-Native',
      desc: 'Your health data belongs to you—not third-party ad networks or subscription servers. Runalyst reads and writes exclusively to your iPhone local SwiftData store and Apple HealthKit.',
      b1: 'No account creation, no email signups, and zero cloud tracking',
      b2: 'Apple HealthKit background observer for instant post-run sync',
      b3: 'Complete data ownership: export or delete your history with one tap'
    }
  };

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const key = tab.getAttribute('data-tab');
      if (!cardData[key]) return;

      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');

      if (!img) return;

      // Smooth scale and fade transition
      img.style.opacity = '0';
      img.style.transform = 'scale(0.97)';

      setTimeout(() => {
        const data = cardData[key];
        img.src = data.src;
        if (badge) badge.textContent = data.badge;
        if (title) title.textContent = data.title;
        if (desc) desc.textContent = data.desc;
        if (bullet1) bullet1.textContent = data.b1;
        if (bullet2) bullet2.textContent = data.b2;
        if (bullet3) bullet3.textContent = data.b3;

        img.style.opacity = '1';
        img.style.transform = 'scale(1)';
      }, 160);
    });
  });
}

/* ==========================================================================
   3. Video Playback & Autoplay Controls
   ========================================================================== */
function initVideoPlayback() {
  const video = document.querySelector('.phone-screen-video, .hero-video, .iphone-video, .phone-video');
  if (!video) return;

  video.play().catch(() => {
    document.addEventListener('click', () => video.play(), { once: true });
  });
}

/* ==========================================================================
   4. Mobile Hamburger Menu & Drawer
   ========================================================================== */
function initMobileMenu() {
  const toggle = document.getElementById('mobile-toggle');
  const drawer = document.getElementById('mobile-drawer');
  if (!toggle || !drawer) return;

  function toggleMenu(open) {
    const shouldOpen = typeof open === 'boolean' ? open : !drawer.classList.contains('is-open');
    if (shouldOpen) {
      drawer.classList.add('is-open');
      toggle.classList.add('is-active');
      toggle.setAttribute('aria-expanded', 'true');
      drawer.setAttribute('aria-hidden', 'false');
    } else {
      drawer.classList.remove('is-open');
      toggle.classList.remove('is-active');
      toggle.setAttribute('aria-expanded', 'false');
      drawer.setAttribute('aria-hidden', 'true');
    }
  }

  toggle.addEventListener('click', (e) => {
    e.stopPropagation();
    toggleMenu();
  });

  // Close when clicking any nav link
  drawer.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => {
      toggleMenu(false);
    });
  });

  // Close when clicking outside drawer
  document.addEventListener('click', (e) => {
    if (drawer.classList.contains('is-open') && !drawer.contains(e.target) && !toggle.contains(e.target)) {
      toggleMenu(false);
    }
  });

  // Close on Escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && drawer.classList.contains('is-open')) {
      toggleMenu(false);
    }
  });
}

/* ==========================================================================
   5. Scroll-Based Fade-In Animations
   ========================================================================== */
function initScrollAnimations() {
  const targets = document.querySelectorAll('.fade-in-section');
  if (!targets.length) return;

  if (!('IntersectionObserver' in window)) {
    targets.forEach(el => el.classList.add('is-visible'));
    return;
  }

  const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        obs.unobserve(entry.target);
      }
    });
  }, {
    rootMargin: '0px 0px -40px 0px',
    threshold: 0.08
  });

  targets.forEach(el => observer.observe(el));
}

/* ==========================================================================
   6. Sticky Header Active-Link Highlighting (ScrollSpy)
   ========================================================================== */
function initScrollSpy() {
  const navLinks = document.querySelectorAll('.nav-links .nav-link');
  const sections = document.querySelectorAll('section[id]');
  if (!navLinks.length || !sections.length) return;

  if (!('IntersectionObserver' in window)) return;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const id = entry.target.getAttribute('id');
        navLinks.forEach(link => {
          const href = link.getAttribute('href');
          if (href === `#${id}`) {
            link.classList.add('active');
          } else {
            link.classList.remove('active');
          }
        });
      }
    });
  }, {
    rootMargin: '-25% 0px -65% 0px',
    threshold: 0
  });

  sections.forEach(sec => observer.observe(sec));
}

