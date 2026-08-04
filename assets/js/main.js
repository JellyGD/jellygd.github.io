// =============================================================
// JellyGD · 暗色科技风主题交互（原生 JS，无依赖）
// =============================================================
(function () {
  'use strict';

  // ---- 移动端导航 ----
  var toggle = document.getElementById('nav-toggle');
  var nav = document.getElementById('site-nav');
  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    nav.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        nav.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  // ---- 顶部阅读进度条 ----
  var bar = document.getElementById('progress-bar');
  // ---- 返回顶部 ----
  var toTop = document.getElementById('to-top');

  function onScroll() {
    var doc = document.documentElement;
    var scrollTop = doc.scrollTop || document.body.scrollTop;
    var height = doc.scrollHeight - doc.clientHeight;
    var pct = height > 0 ? (scrollTop / height) * 100 : 0;
    if (bar) bar.style.width = pct + '%';
    if (toTop) toTop.classList.toggle('show', scrollTop > 400);
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  if (toTop) {
    toTop.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  // ---- 代码块：包裹容器 + 复制按钮 ----
  function enhanceCodeBlocks() {
    var blocks = document.querySelectorAll('div.highlight');
    blocks.forEach(function (block) {
      if (block.parentNode && block.parentNode.classList.contains('code-block')) return;
      var wrap = document.createElement('div');
      wrap.className = 'code-block';
      block.parentNode.insertBefore(wrap, block);
      wrap.appendChild(block);

      var btn = document.createElement('button');
      btn.className = 'copy-btn';
      btn.type = 'button';
      btn.textContent = '复制';
      btn.addEventListener('click', function () {
        var code = block.querySelector('code');
        var text = code ? code.innerText : block.innerText;
        var done = function () {
          btn.textContent = '已复制';
          btn.classList.add('done');
          setTimeout(function () {
            btn.textContent = '复制';
            btn.classList.remove('done');
          }, 1600);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, fallbackCopy);
        } else {
          fallbackCopy();
        }
        function fallbackCopy() {
          var ta = document.createElement('textarea');
          ta.value = text;
          ta.style.position = 'fixed';
          ta.style.opacity = '0';
          document.body.appendChild(ta);
          ta.select();
          try { document.execCommand('copy'); done(); } catch (e) {}
          document.body.removeChild(ta);
        }
      });
      wrap.appendChild(btn);
    });
  }
  enhanceCodeBlocks();
})();
