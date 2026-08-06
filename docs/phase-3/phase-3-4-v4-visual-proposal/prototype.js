/* Lyric Island V3 & V4 Interactive Prototype Logic */

document.addEventListener("DOMContentLoaded", () => {
  const stage = document.getElementById("macWindowStage");
  const quietToolbar = document.getElementById("quietToolbar");
  const btnWorkbench = document.getElementById("btnWorkbench");
  const inspectorSidebar = document.getElementById("inspectorSidebar");
  const smallBottomSheet = document.getElementById("smallBottomSheet");
  const secondaryBanner = document.getElementById("secondaryBanner");
  const lyricsContainer = document.getElementById("lyricsContainer");
  const playPauseBtn = document.getElementById("playPauseBtn");
  const v3BadgeText = document.getElementById("v3BadgeText");

  let currentPresentation = "v4"; // v4 | v3
  let currentVariant = "A";
  let currentMode = "wide"; // wide | small | focus
  let currentLyricsPolicy = "translation"; // translation | ruby
  let isInspectorOpen = false;
  let isSmallSheetOpen = false;
  let isHoveredToolbar = false;
  let isPlaying = true;
  let currentStatusState = "none"; // none | idle | noLyrics | networkError | syncing

  // Presentation Style Switcher (V3 Apple Music vs V4 Direction D)
  window.setPresentationStyle = (style) => {
    currentPresentation = style;
    document.querySelectorAll(".btn-pres").forEach(btn => btn.classList.remove("active"));
    document.getElementById(`btnPres${style.toUpperCase()}`).classList.add("active");

    if (style === "v3") {
      stage.classList.add("style-v3");
      stage.classList.remove("variant-b");
      btnWorkbench.style.display = "none"; // V3 uses classic layout without V4 Workbench button
      if (v3BadgeText) v3BadgeText.style.display = "inline-block";
      inspectorSidebar.style.display = "none";
      isInspectorOpen = false;
    } else {
      stage.classList.remove("style-v3");
      btnWorkbench.style.display = "flex";
      if (v3BadgeText) v3BadgeText.style.display = "none";
    }

    renderLyrics();
  };

  // Variant Switcher (V4 Variant A vs Variant B)
  window.setVariant = (variant) => {
    if (currentPresentation === "v3") {
      alert("变体 A / B 为 V4 Direction D 专属参数变体。当前处于 V3 Apple Music 沉浸模式。");
      return;
    }
    currentVariant = variant;
    document.querySelectorAll(".btn-variant").forEach(btn => btn.classList.remove("active"));
    document.getElementById(`btnVar${variant}`).classList.add("active");

    if (variant === "B") {
      stage.classList.add("variant-b");
    } else {
      stage.classList.remove("variant-b");
    }
  };

  // Window Mode Switcher
  window.setWindowMode = (mode) => {
    currentMode = mode;
    document.querySelectorAll(".btn-mode").forEach(btn => btn.classList.remove("active"));
    document.getElementById(`btnMode${capitalize(mode)}`).classList.add("active");

    stage.classList.remove("mode-wide", "mode-small", "mode-focus");
    stage.classList.add(`mode-${mode}`);

    if (mode === "small") {
      inspectorSidebar.style.display = "none";
      if (isInspectorOpen && currentPresentation === "v4") {
        isSmallSheetOpen = true;
        smallBottomSheet.style.display = "flex";
      }
    } else {
      smallBottomSheet.style.display = "none";
      if (isInspectorOpen && currentPresentation === "v4") {
        inspectorSidebar.style.display = "flex";
      }
    }
  };

  window.toggleInspector = () => {
    if (currentPresentation === "v3") {
      alert("V3 模式为 Apple Music 沉浸经典主窗口；按 ⌘I 或选择 V4 可体验 [歌曲工作台] 模式。");
      return;
    }
    if (currentMode === "small") {
      isSmallSheetOpen = !isSmallSheetOpen;
      smallBottomSheet.style.display = isSmallSheetOpen ? "flex" : "none";
      btnWorkbench.classList.toggle("active", isSmallSheetOpen);
    } else {
      isInspectorOpen = !isInspectorOpen;
      inspectorSidebar.style.display = isInspectorOpen ? "flex" : "none";
      btnWorkbench.classList.toggle("active", isInspectorOpen);
      quietToolbar.classList.toggle("force-hover", isInspectorOpen);
    }
  };

  window.setToolbarHover = (hover) => {
    isHoveredToolbar = hover;
    quietToolbar.classList.toggle("force-hover", hover || isInspectorOpen);
  };

  window.setLyricsPolicy = (policy) => {
    currentLyricsPolicy = policy;
    document.querySelectorAll(".btn-policy").forEach(btn => btn.classList.remove("active"));
    document.getElementById(`btnPolicy${capitalize(policy)}`).classList.add("active");

    renderLyrics();
  };

  window.setPlaybackState = (playing) => {
    isPlaying = playing;
    playPauseBtn.className = playing ? "btn-control-play ri-pause-circle-fill" : "btn-control-play ri-play-circle-fill";
  };

  window.setStatusState = (state) => {
    currentStatusState = state;
    document.querySelectorAll(".btn-status").forEach(btn => btn.classList.remove("active"));
    document.getElementById(`btnStatus${capitalize(state)}`).classList.add("active");

    if (state === "none") {
      secondaryBanner.style.display = "none";
      renderLyrics();
    } else if (state === "idle") {
      secondaryBanner.style.display = "none";
      renderEmptyState("等待 Spotify 播放", "ri-music-fill");
    } else if (state === "noLyrics") {
      secondaryBanner.style.display = "none";
      renderEmptyState("暂未找到歌词", "ri-search-line", true);
    } else if (state === "networkError") {
      secondaryBanner.style.display = "none";
      renderEmptyState("网络连接失败", "ri-wifi-off-line", false, true);
    } else if (state === "syncing") {
      secondaryBanner.style.display = "flex";
      secondaryBanner.querySelector(".status-text").textContent = "正在同步歌词...";
      renderLyrics();
    }
  };

  window.toggleContextMenu = (rowIdx) => {
    const popover = document.getElementById(`contextMenu_${rowIdx}`);
    if (popover) {
      const isVisible = popover.style.display === "flex";
      document.querySelectorAll(".context-menu-popover").forEach(p => p.style.display = "none");
      popover.style.display = isVisible ? "none" : "flex";
    }
  };

  function capitalize(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

  function renderLyrics() {
    lyricsContainer.innerHTML = `
      <div class="lyric-row distant">
        <div class="lyric-original">僧に成り損ないの貧乏学生</div>
      </div>
      <div class="lyric-row hero">
        ${currentLyricsPolicy === "ruby" ? '<div class="lyric-ruby">とうきょう は よる しちじ あわただしい まち に あめ が ふりだす</div>' : ''}
        <div class="lyric-original">東京は夜七時 慌ただしい街に雨が降り出す</div>
        ${currentLyricsPolicy === "translation" ? '<div class="lyric-translation">东京晚上七点 匆忙的街头开始下起了雨</div>' : ''}
        <div class="context-dot" onclick="toggleContextMenu(1)">
          <i class="ri-more-fill"></i>
          <div class="context-menu-popover" id="contextMenu_1" style="display: none;">
            <div class="menu-item" onclick="alert('修正译文')"><i class="ri-edit-line"></i> 修正译文</div>
            <div class="menu-item" onclick="alert('调整注音')"><i class="ri-text-spacing"></i> 调整注音</div>
            <div class="menu-item" onclick="alert('校准时间')"><i class="ri-timer-line"></i> 校准时间</div>
          </div>
        </div>
      </div>
      <div class="lyric-row adjacent">
        <div class="lyric-original">領収書を書いて頂戴 税理士と六本木で会うから</div>
        ${currentLyricsPolicy === "translation" ? '<div class="lyric-translation">请开具收据 我要与税务师在六本木见面</div>' : ''}
      </div>
      <div class="lyric-row distant">
        <div class="lyric-original">そっと抱き寄せて耳元で囁く</div>
      </div>
    `;
  }

  function renderEmptyState(title, iconClass, showSearchBtn = false, showRetryBtn = false) {
    lyricsContainer.innerHTML = `
      <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; width: 100%; height: 300px; gap: 16px; text-align: center;">
        <i class="${iconClass}" style="font-size: 40px; color: rgba(255,255,255,0.4);"></i>
        <div style="font-size: 16px; font-weight: 600; color: rgba(255,255,255,0.85);">${title}</div>
        ${showSearchBtn ? '<div style="display: flex; gap: 10px;"><button class="btn-tag active" onclick="alert(\'打开手动搜索\')">手动搜索</button><button class="btn-tag" onclick="alert(\'导入本地歌词\')">导入歌词</button></div>' : ''}
        ${showRetryBtn ? '<button class="btn-tag active" onclick="setStatusState(\'none\')">重新尝试</button>' : ''}
      </div>
    `;
  }

  renderLyrics();
});
