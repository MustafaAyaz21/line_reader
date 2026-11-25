// Interactive Demo Dictionary for the Hero Phone Mockup
const demoWords = {
  tr: {
    effortless: {
      word: "effortless",
      pos: "sıfat",
      ipa: "/ˈef.ət.ləs/ · UK",
      meaning: "zahmetsiz, kolayca yapılan",
      context: 'Bu cümlede: "yabancı dilde okumak zahmetsiz hale gelir"',
    },
    curiosity: {
      word: "curiosity",
      pos: "isim",
      ipa: "/ˌkjʊə.riˈɒs.ə.ti/ · UK",
      meaning: "merak, öğrenme isteği",
      context: 'Bu cümlede: "bırak merakın sana hikâye boyunca rehberlik etsin"',
    },
    momentum: {
      word: "momentum",
      pos: "isim",
      ipa: "/məˈmen.təm/ · US",
      meaning: "ivme, hız kazanma",
      context: 'Bu cümlede: "satır satır ilerleyerek ivme kazan"',
    },
    remarkable: {
      word: "remarkable",
      pos: "sıfat",
      ipa: "/rɪˈmɑː.kə.bəl/ · UK",
      meaning: "dikkate değer, olağanüstü",
      context: 'Bu cümlede: "kısa bir günlük alışkanlık bile olağanüstü gelişim sağlar"',
    },
  },
  en: {
    effortless: {
      word: "effortless",
      pos: "adjective",
      ipa: "/ˈef.ət.ləs/ · UK",
      meaning: "requiring no physical or mental exertion; natural",
      context: 'In this sentence: "reading becomes effortless and smooth"',
    },
    curiosity: {
      word: "curiosity",
      pos: "noun",
      ipa: "/ˌkjʊə.riˈɒs.ə.ti/ · UK",
      meaning: "a strong desire to know or learn something",
      context: 'In this sentence: "let curiosity guide you through the story"',
    },
    momentum: {
      word: "momentum",
      pos: "noun",
      ipa: "/məˈmen.təm/ · US",
      meaning: "strength or speed gained over time",
      context: 'In this sentence: "build steady momentum line by line"',
    },
    remarkable: {
      word: "remarkable",
      pos: "adjective",
      ipa: "/rɪˈmɑː.kə.bəl/ · UK",
      meaning: "worthy of attention; extraordinary",
      context: 'In this sentence: "even a brief daily habit creates remarkable progress"',
    },
  },
};

const i18n = {
  tr: {
    pageTitle: "Line Reader — İngilizce Okuma ve Akıllı Kelime Öğrenme Uygulaması",
    navFeatures: "Özellikler",
    navThemes: "Temalar",
    navHow: "Nasıl Çalışır?",
    navCta: "Ücretsiz İndir",
    heroTitleLine1: "İngilizce okurken",
    heroTitleLine2: "akışını hiç bozma.",
    heroDesc:
      "Line Reader, okuduğun her satırda bilmediğin kelimelere tek dokunuşla bağlam odaklı Türkçe anlam, IPA telaffuz ve sesli okuma sunar. Makale okurken ya da web'de gezinirken kelime hazineni zahmetsizce büyüt.",
    heroDownloadLabel: "Android APK İndir",
    heroWebAppBtn: "Web'de Aç",
    heroExploreBtn: "Özellikleri Keşfet",
    stat1: "Seviyeli Makaleler",
    stat2Strong: "AI + Çevrimdışı",
    stat2: "Hibrit Sözlük",
    stat3: "IPA & Sesli Okuma",
    mockupLevel: "B1 · Orta Seviye",
    mockupHint: "Kelimelere tıkla 👇",
    mockupAiTag: "✦ Bağlam Çevirisi",
    saveDefault: "+ Listeme Ekle",
    saveAdded: "✓ Listeye Eklendi",
    featuresKicker: "Neden Line Reader?",
    featuresTitle: "Okuma alışkanlığını dil öğrenme motoruna dönüştür",
    featuresDesc:
      "Sözlük uygulamaları arasında geçiş yapmadan, odağını kaybetmeden ve tamamen kendi hızında öğren.",
    f1Title: "Bağlam Odaklı AI Çeviri",
    f1Desc:
      "Kelimenin sadece sözlük karşılığını değil, tam olarak okuduğun cümledeki gerçek anlamını yapay zekâ ve hızlı yerel sözlük desteğiyle anında gör.",
    f2Title: "Seviyeli İngilizce Makaleler",
    f2Desc:
      "Başlangıçtan ileri seviyeye kadar özenle hazırlanmış içeriklerle oku, kaldığın yeri otomatik takip et ve paragraf çevirileriyle anladığını doğrula.",
    f3Title: "Gömülü Tarayıcı & Overlay",
    f3Desc:
      "Uygulama içi tarayıcıyla sevdiğin yabancı haber ve blog sitelerini oku. Üstelik telefonundaki diğer uygulamalarda metin seçtiğinde bile anında çeviri penceresi açılır.",
    f4Title: "Kişisel Kelime Havuzu",
    f4Desc:
      "Yeni öğrendiğin kelimeleri tek dokunuşla kendi listelerine kaydet. Kök/ek çözümleyici sayesinde çekimli kelimelerin bile temel hallerini kolayca yakala.",
    f5Title: "IPA Telaffuz & Sesli Okuma",
    f5Desc:
      "İngiliz (UK) veya Amerikan (US) aksan tercihinle kelimelerin fonetik yazımını gör, hem tek tek kelimeleri hem de tüm makaleyi sesli dinle.",
    f6Title: "Animasyonlu & Rahat Temalar",
    f6Desc:
      "Gece okumalarını keyfe dönüştüren hareketli galaksi, okyanus, sıcak latte ve pastel temalarla uygulamanı tamamen kendi zevkine göre kişiselleştir.",
    themeKicker: "Kişiselleştirme",
    themeTitle: "Ruh haline uygun okuma atmosferi",
    themeDesc:
      "Line Reader, gözünü yormayan statik ve canlı animasyonlu temalarla gelir. Aşağıdan temalara tıklayarak okuma kartının nasıl değiştiğini anında dene.",
    themeNight: "Gece Derinliği",
    themeAmethyst: "Ametist Galaksi",
    themeOcean: "Okyanus Derinlikleri",
    themeLatte: "Sıcak Latte",
    themeSage: "Adaçayı & Gün Işığı",
    stageTranslation: "“Kitapsız bir oda, ruhsuz bir beden gibidir.”",
    howKicker: "3 Adımda Başla",
    howTitle: "Dakikalar içinde okumaya hazır",
    step1Title: "Uygulamayı İndir",
    step1Desc: "Güncel Android APK dosyasını tek tıkla indir ve telefonuna güvenle kur.",
    step2Title: "İçeriğini Seç",
    step2Desc: "Seviyene uygun makalelerden birini aç ya da gömülü tarayıcıyla internette oku.",
    step3Title: "Dokun & Öğren",
    step3Desc: "Takıldığın kelimeye dokun, bağlam anlamını ve telaffuzunu gör, listene kaydet.",
    ctaTitle: "Line Reader'ı hemen dene",
    ctaDesc: "Tamamen ücretsiz olarak indir, İngilizce okuma alışkanlığını bugün başlat.",
    ctaWebAppBtn: "Tarayıcıda Aç (Web)",
    note1: "Android 7.0+ uyumlu",
    note2: "Doğrudan GitHub Releases üzerinden güvenli indirme",
    note3: "Uygulama içi otomatik sürüm bildirimi",
    footerCopy: "© 2026 Line Reader. Tüm hakları saklıdır.",
  },
  en: {
    pageTitle: "Line Reader — English Reading & Smart Vocabulary App",
    navFeatures: "Features",
    navThemes: "Themes",
    navHow: "How It Works",
    navCta: "Free Download",
    heroTitleLine1: "Read in English,",
    heroTitleLine2: "never break your flow.",
    heroDesc:
      "Line Reader gives you instant context-aware word meanings, IPA pronunciation, and natural voice playback with a single tap. Grow your vocabulary effortlessly while reading articles or browsing the web.",
    heroDownloadLabel: "Download Android APK",
    heroWebAppBtn: "Open Web App",
    heroExploreBtn: "Explore Features",
    stat1: "Leveled Articles",
    stat2Strong: "AI + Offline",
    stat2: "Hybrid Dictionary",
    stat3: "IPA & Audio",
    mockupLevel: "B1 · Intermediate",
    mockupHint: "Tap any word 👇",
    mockupAiTag: "✦ Context Lookup",
    saveDefault: "+ Add to List",
    saveAdded: "✓ Saved to List",
    featuresKicker: "Why Line Reader?",
    featuresTitle: "Turn your reading habit into a language engine",
    featuresDesc:
      "Learn at your own pace without switching between dictionary apps or losing focus.",
    f1Title: "Context-Aware AI Lookup",
    f1Desc:
      "See the exact meaning of a word in the sentence you are reading, powered by AI and a fast offline dictionary.",
    f2Title: "Leveled English Articles",
    f2Desc:
      "Read curated articles from beginner to advanced levels, track your reading progress automatically, and check comprehension with sentence translations.",
    f3Title: "Built-in Browser & Overlay",
    f3Desc:
      "Read your favorite foreign news and blogs in the in-app browser, or highlight text in any Android app for an instant floating lookup card.",
    f4Title: "Personal Word Lists",
    f4Desc:
      "Save newly learned words to custom lists with one tap. Built-in morphology helps match inflected words to their base forms.",
    f5Title: "IPA Pronunciation & TTS",
    f5Desc:
      "View phonetic transcriptions in British (UK) or American (US) English and listen to individual words or full articles aloud.",
    f6Title: "Calm & Animated Themes",
    f6Desc:
      "Personalize your reading space with battery-friendly animated galaxy, ocean, warm latte, and pastel themes.",
    themeKicker: "Personalization",
    themeTitle: "A reading atmosphere for every mood",
    themeDesc:
      "Line Reader includes eye-friendly static and calm animated themes. Click the pills below to preview the reading card live.",
    themeNight: "Night Depth",
    themeAmethyst: "Amethyst Galaxy",
    themeOcean: "Ocean Depths",
    themeLatte: "Warm Latte",
    themeSage: "Sage & Sunlight",
    stageTranslation: "“Reading without distraction makes every page memorable.”",
    howKicker: "Start in 3 Steps",
    howTitle: "Ready to read in minutes",
    step1Title: "Download the App",
    step1Desc: "Download the latest Android APK with one tap and install it safely on your phone.",
    step2Title: "Pick Your Content",
    step2Desc: "Open an article tailored to your level or browse the web with the built-in browser.",
    step3Title: "Tap & Learn",
    step3Desc: "Tap any unfamiliar word to see its contextual meaning, pronunciation, and save it.",
    ctaTitle: "Try Line Reader today",
    ctaDesc: "Download completely free and start building your daily English reading habit.",
    ctaWebAppBtn: "Open in Browser (Web)",
    note1: "Android 7.0+ compatible",
    note2: "Secure direct download via GitHub Releases",
    note3: "Automatic in-app update notifications",
    footerCopy: "© 2026 Line Reader. All rights reserved.",
  },
};

let currentLang = "tr";
let latestReleaseTag = "v0.1.32";
let currentThemeKey = "night-depth";

const savedWords = new Set();
let currentWordKey = "effortless";

const wordButtons = document.querySelectorAll(".word-token");
const lookupWord = document.getElementById("lookupWord");
const lookupPos = document.getElementById("lookupPos");
const lookupIpa = document.getElementById("lookupIpa");
const lookupMeaning = document.getElementById("lookupMeaning");
const lookupContext = document.getElementById("lookupContext");
const saveWordBtn = document.getElementById("saveWordBtn");
const speakBtn = document.getElementById("speakBtn");

function updateSaveButton() {
  if (!saveWordBtn) return;
  const dict = i18n[currentLang];
  if (savedWords.has(currentWordKey)) {
    saveWordBtn.textContent = dict.saveAdded;
    saveWordBtn.classList.add("saved");
  } else {
    saveWordBtn.textContent = dict.saveDefault;
    saveWordBtn.classList.remove("saved");
  }
}

function selectWord(key) {
  const dict = demoWords[currentLang] || demoWords.tr;
  const entry = dict[key];
  if (!entry) return;
  currentWordKey = key;

  wordButtons.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.word === key);
  });

  lookupWord.textContent = entry.word;
  lookupPos.textContent = entry.pos;
  lookupIpa.textContent = entry.ipa;
  lookupMeaning.textContent = entry.meaning;
  lookupContext.textContent = entry.context;
  updateSaveButton();
}

wordButtons.forEach((btn) => {
  btn.addEventListener("click", () => selectWord(btn.dataset.word));
});

if (saveWordBtn) {
  saveWordBtn.addEventListener("click", () => {
    if (savedWords.has(currentWordKey)) {
      savedWords.delete(currentWordKey);
    } else {
      savedWords.add(currentWordKey);
    }
    updateSaveButton();
  });
}

if (speakBtn) {
  speakBtn.addEventListener("click", () => {
    if ("speechSynthesis" in window) {
      window.speechSynthesis.cancel();
      const utterance = new SpeechSynthesisUtterance(currentWordKey);
      utterance.lang = "en-US";
      utterance.rate = 0.92;
      window.speechSynthesis.speak(utterance);
    }
  });
}

// Interactive Theme Switcher
const themeMeta = {
  tr: {
    "night-depth": { title: "Gece Derinliği", type: "Koyu Tema" },
    "amethyst-galaxy": { title: "Ametist Galaksi", type: "Animasyonlu Tema" },
    "ocean-depths": { title: "Okyanus Derinlikleri", type: "Animasyonlu Tema" },
    "warm-latte": { title: "Sıcak Latte", type: "Animasyonlu Açık Tema" },
    "sage-sunlight": { title: "Adaçayı & Gün Işığı", type: "Animasyonlu Açık Tema" },
  },
  en: {
    "night-depth": { title: "Night Depth", type: "Dark Theme" },
    "amethyst-galaxy": { title: "Amethyst Galaxy", type: "Animated Theme" },
    "ocean-depths": { title: "Ocean Depths", type: "Animated Theme" },
    "warm-latte": { title: "Warm Latte", type: "Animated Light Theme" },
    "sage-sunlight": { title: "Sage & Sunlight", type: "Animated Light Theme" },
  },
};

const themePills = document.querySelectorAll(".theme-pill");
const themeStage = document.getElementById("themeStage");
const stageBadge = document.getElementById("stageBadge");
const stageType = document.getElementById("stageType");

function updateThemeStage(theme) {
  const metaMap = themeMeta[currentLang] || themeMeta.tr;
  const meta = metaMap[theme];
  if (!meta || !themeStage) return;
  currentThemeKey = theme;

  themePills.forEach((p) =>
    p.classList.toggle("active", p.dataset.theme === theme)
  );

  themeStage.className = `theme-preview-stage theme-${theme}`;
  stageBadge.textContent = meta.title;
  stageType.textContent = meta.type;
}

themePills.forEach((pill) => {
  pill.addEventListener("click", () => updateThemeStage(pill.dataset.theme));
});

function updateReleaseLabels() {
  const badgeTextEl = document.getElementById("releaseBadgeText");
  const heroVerEl = document.getElementById("heroDownloadVer");
  const ctaTextEl = document.getElementById("ctaDownloadText");

  if (badgeTextEl) {
    badgeTextEl.textContent =
      currentLang === "en"
        ? `Android ${latestReleaseTag} Live`
        : `Android ${latestReleaseTag} Yayında`;
  }
  if (heroVerEl) {
    heroVerEl.textContent = latestReleaseTag;
  }
  if (ctaTextEl) {
    ctaTextEl.textContent =
      currentLang === "en"
        ? `Download Line Reader APK (${latestReleaseTag})`
        : `Line Reader APK İndir (${latestReleaseTag})`;
  }
}

function applyLanguage(lang) {
  currentLang = lang === "en" ? "en" : "tr";
  const dict = i18n[currentLang];
  document.documentElement.lang = currentLang;
  document.title = dict.pageTitle;

  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    if (key && dict[key] !== undefined) {
      el.textContent = dict[key];
    }
  });

  const langToggleBtn = document.getElementById("langToggle");
  const langToggleLabel = document.getElementById("langToggleLabel");
  if (langToggleLabel) {
    langToggleLabel.textContent = currentLang === "tr" ? "EN" : "TR";
  }
  if (langToggleBtn) {
    langToggleBtn.setAttribute(
      "aria-label",
      currentLang === "tr"
        ? "Switch language to English"
        : "Dili Türkçe yap"
    );
  }

  selectWord(currentWordKey);
  updateThemeStage(currentThemeKey);
  updateReleaseLabels();

  try {
    localStorage.setItem("linereader_web_lang", currentLang);
  } catch (_) {}
}

const langToggle = document.getElementById("langToggle");
if (langToggle) {
  langToggle.addEventListener("click", () => {
    applyLanguage(currentLang === "tr" ? "en" : "tr");
  });
}

try {
  const savedLang = localStorage.getItem("linereader_web_lang");
  if (savedLang === "en") {
    applyLanguage("en");
  }
} catch (_) {}

// Mobile Nav Toggle
const menuToggle = document.getElementById("menuToggle");
const navLinks = document.getElementById("navLinks");

if (menuToggle && navLinks) {
  menuToggle.addEventListener("click", () => {
    const isOpen = navLinks.classList.toggle("open");
    menuToggle.setAttribute("aria-expanded", String(isOpen));
  });

  navLinks.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      navLinks.classList.remove("open");
      menuToggle.setAttribute("aria-expanded", "false");
    });
  });
}

// Scroll Reveal
const revealEls = document.querySelectorAll(".reveal");
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.12 }
);

revealEls.forEach((el) => observer.observe(el));

// Auto-sync Latest Release Version & APK URL from GitHub
(async function syncLatestRelease() {
  const badgeTextEl = document.getElementById("releaseBadgeText");
  const heroBtn = document.getElementById("heroDownloadBtn");
  const heroVerEl = document.getElementById("heroDownloadVer");
  const ctaBtn = document.getElementById("ctaDownloadBtn");
  const ctaTextEl = document.getElementById("ctaDownloadText");

  function applyRelease(tag, apkUrl) {
    if (!tag) return;
    latestReleaseTag = tag.startsWith("v") ? tag : `v${tag}`;
    updateReleaseLabels();
    if (apkUrl) {
      if (heroBtn) heroBtn.href = apkUrl;
      if (ctaBtn) ctaBtn.href = apkUrl;
    }
  }

  try {
    const res = await fetch(
      "https://api.github.com/repos/MustafaAyaz21/line_reader/releases/latest",
      { headers: { Accept: "application/vnd.github+json" } }
    );
    if (res.ok) {
      const data = await res.json();
      const tag = data && data.tag_name ? String(data.tag_name).trim() : "";
      const apkAsset = Array.isArray(data?.assets)
        ? data.assets.find((a) => String(a?.name || "").endsWith(".apk"))
        : null;
      if (tag) {
        applyRelease(tag, apkAsset?.browser_download_url);
        return;
      }
    }
  } catch (_) {
    // Fallback to raw version.json below
  }

  try {
    const res = await fetch(
      "https://raw.githubusercontent.com/MustafaAyaz21/line_reader/main/version.json",
      { cache: "no-store" }
    );
    if (res.ok) {
      const data = await res.json();
      const version = data && data.version ? String(data.version).trim() : "";
      const apkUrl = data && data.apk_url ? String(data.apk_url).trim() : "";
      if (version) {
        applyRelease(version, apkUrl);
      }
    }
  } catch (_) {
    // Keep default fallback in HTML
  }
})();
