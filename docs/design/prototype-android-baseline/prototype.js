// 기존 6화면과 현행 계약 기반 Android 기준안을 한 URL에서 전환·비교하는 폐기용 프로토타입 로직.
const screens = [
  {
    key: 'onboarding',
    number: '01',
    title: '온보딩',
    original: '../prototype/01-onboarding.html',
    contract: '별도 랜딩이 아니라 메인 탭의 첫 상태. 레시피 북 3개 저장을 그 자리에서 완결하거나 건너뛴다.',
    review: [
      'Android 셸(앱바·하단 탭) 안에서도 브랜드 첫인상이 충분한가?',
      '히어로 200px와 인라인 레시피 저장 카드의 시각적 무게가 균형 잡혔는가?',
      '네이티브에서는 카톡 내부 브라우저 경고가 사라지는 것이 자연스러운가?',
    ],
  },
  {
    key: 'recognition',
    number: '02',
    title: '재료 인식',
    original: '../prototype/02-recognition.html',
    contract: '메인 셸을 유지하고 실제 업로드 사진을 보여준다. 진행률은 경과 단계이며 알 수 없는 재료 개수는 말하지 않는다.',
    review: [
      '전용 “재료 인식” 화면 대신 메인 셸 안에서 기다리는 구성이 명확한가?',
      '4:3 사진·스캔 시머·체크리스트 스켈레톤의 비중이 적절한가?',
      '“다른 사진으로 다시”가 취소 대신 반복 진입점으로 읽히는가?',
    ],
  },
  {
    key: 'checklist',
    number: '03',
    title: '재료 체크리스트',
    original: '../prototype/03-checklist.html',
    contract: 'confidence 3단과 뭉뚱그림 항목을 보존하고, 수동 추가 바를 메인 탭 안에 고정한다.',
    review: [
      'high·medium·low의 차이가 색에만 의존하지 않고 한눈에 읽히는가?',
      '뭉뚱그림 항목이 일반 재료와 분리되고 치환 전 매칭 제외로 느껴지는가?',
      '긴 체크리스트에서 하단 추가 바가 주 CTA를 압도하지 않는가?',
    ],
  },
  {
    key: 'suggestions',
    number: '04',
    title: '제안',
    original: '../prototype/04-suggestions.html',
    contract: '직전 재료는 한 줄로 접고 오늘 할 3개를 세로로 쌓는다. 낡음 배너는 실제 수정 뒤에만 나타난다.',
    review: [
      '접힌 재료 체크리스트가 맥락을 남기되 제안보다 앞서지 않는가?',
      '레시피 대표 이미지·라벨·출처·실행 버튼의 위계가 한 카드 안에서 명확한가?',
      '초기 제안 상태에서 오래된 목업의 낡음 배너를 제거한 것이 자연스러운가?',
    ],
  },
  {
    key: 'detail',
    number: '05',
    title: '제안 상세',
    original: '../prototype/05-suggestion-detail.html',
    contract: '유일한 push 화면. 대표 이미지, 파생한 있는 재료, 부족 재료와 고정 “이거 했어요”를 한 흐름으로 보여준다.',
    review: [
      '탭 바 없이도 뒤로가기와 메인 복귀가 명백한가?',
      '데이터가 없는 이어보기 시각은 버리고 “영상 보기”만 남긴 것이 정직한가?',
      '비상호작용 “담기” 칩이 버튼으로 오인되지 않는가?',
    ],
  },
  {
    key: 'recipe-book',
    number: '06',
    title: '레시피 북',
    original: '../prototype/06-recipe-book.html',
    contract: 'URL과 제목을 받아 재료 추출을 시작하고, 사용자가 고른 대표 이미지와 저장 자산을 그룹 리스트로 보여준다.',
    review: [
      '두 입력 필드가 필요한 현행 저장 계약이 과도한 마찰 없이 보이는가?',
      '44×44 대표 이미지가 목록 식별성을 충분히 높이는가?',
      '가짜 30개 한도 크롬이 실제 저장 제한으로 오해되지 않는가?',
    ],
  },
];

const icon = (name, className = '') =>
  `<svg class="icon ${className}" aria-hidden="true"><use href="#i-${name}"></use></svg>`;

const statusBar = (detail = false) => `
  <div class="statusbar ${detail ? 'detail-status' : ''}">
    <span class="numeric">9:41</span>
    <span class="status-icons"><span>LTE</span><span>▴▴</span><span>▰</span><i class="camera-cutout"></i></span>
  </div>`;

const appBar = (title = '냉파', action = '<button class="text-button" data-go="recipe-book">레시피 북</button>') => `
  <div class="appbar">
    <span class="appbar-title">${title}</span>
    ${action}
  </div>`;

const bottomNav = (active = 'main') => `
  <div class="bottom-nav">
    <button class="${active === 'main' ? 'active' : ''}" data-go="onboarding">${icon('home')}<span>메인</span></button>
    <button class="${active === 'recipe-book' ? 'active' : ''}" data-go="recipe-book">${icon('bookmark')}<span>레시피 북</span></button>
  </div>
  <div class="gesture-area"></div>`;

const shell = ({ body, active = 'main', title = '냉파', action, addBar = '' }) => `
  <div class="app-screen">
    ${statusBar()}
    ${appBar(title, action)}
    <div class="screen-scroll">${body}</div>
    ${addBar}
    ${bottomNav(active)}
  </div>`;

const checked = (medium = false) => `
  <span class="check-box checked">${icon('check')}${medium ? '<i class="question-dot">?</i>' : ''}</span>`;

const onboarding = () => shell({
  body: `
    <section class="brand-hero">
      <div><h3>냉파</h3><p>냉장고 사진 한 장으로,<br>오늘 뭐 해먹을지 끝내요.</p></div>
    </section>
    <div class="spacer-14"></div>
    <p class="trust-line">${icon('check')}<span>출처 있는, 내가 저장한 레시피만 추천해요.</span></p>
    <div class="spacer-12"></div>
    <section class="card onboarding-card">
      <div class="between"><strong class="headline">믿고 보는 레시피 3개만 저장해두세요</strong><span class="counter">0/3</span></div>
      <div class="spacer-8"></div>
      <div class="subhead muted">냉장고 사진과 맞춰볼 근거가 됩니다.</div>
      <div class="spacer-16"></div>
      <input class="field" aria-label="레시피 링크" placeholder="레시피 링크 붙여넣기" />
      <div class="spacer-8"></div>
      <input class="field" aria-label="요리 제목" placeholder="무슨 요리인가요? (예: 김치찌개)" />
      <div class="spacer-12"></div>
      <button class="primary wide">레시피 북에 담기</button>
      <div class="form-caption">제목으로 재료를 짐작해 둡니다. 영상 내용은 가져오지 않아요.</div>
      <button class="text-button wide" data-go="recognition">나중에 할게요</button>
    </section>`,
});

const recognition = () => shell({
  body: `
    <button class="text-button retry-link" data-go="onboarding">다른 사진으로 다시</button>
    <section class="recognition-photo">
      <img src="https://images.unsplash.com/photo-1556911220-bff31c812dba?w=780&q=74&auto=format&fit=crop" alt="업로드한 냉장고 사진" />
      <div class="scan-line"></div>
    </section>
    <div class="spacer-20"></div>
    <div class="center body">재료를 찾는 중이에요</div>
    <div class="spacer-4"></div>
    <div class="center footnote muted">사진에서 재료를 확인하고 있어요.</div>
    <div class="spacer-16"></div>
    <div class="progress"><span style="width:35%"></span></div>
    <div class="spacer-8"></div>
    <div class="caption muted" style="text-align:right">보통 5초 정도 걸려요</div>
    <div class="spacer-16"></div>
    <div class="skeleton-group">
      ${[136, 102, 148, 116, 132].map((width) => `<div class="skeleton-row"><span class="skel box"></span><span class="skel" style="width:${width}px"></span></div>`).join('')}
    </div>`,
});

const checklist = () => shell({
  body: `
    <button class="text-button retry-link">다른 사진으로 다시</button>
    <h3 class="large-title">냉장고에 있는 것</h3>
    <div class="spacer-12"></div>
    <div class="expectation">${icon('info')}<span>사진 인식은 완벽하지 않아요. 맞는 것만 남기고 빠진 건 아래에서 더해 주세요.</span></div>
    <div class="spacer-12"></div>
    <div class="group">
      <div class="ingredient-row">${checked()}<span>양파</span></div>
      <div class="ingredient-row">${checked()}<span>계란</span></div>
      <div class="ingredient-row">${checked(true)}<span>애호박</span><span class="badge buy">확인</span></div>
      <div class="ingredient-row">${checked(true)}<span>당근</span><span class="badge buy">확인</span></div>
    </div>
    <div class="spacer-20"></div>
    <div class="section-label">확실하지 않아요</div>
    <div class="group dim">
      <div class="ingredient-row"><span class="check-box"></span><span>표고버섯?</span></div>
    </div>
    <div class="spacer-20"></div>
    <div class="section-label">이건 뭐였나요?</div>
    <div class="vague-card between"><span class="muted">소스류</span><button class="text-button">맞아요</button></div>
    <div class="spacer-16"></div>
    <button class="primary wide" data-go="suggestions">오늘 뭐 해먹지</button>`,
  addBar: `
    <div class="add-bar">
      <div class="rowflex"><input class="field" placeholder="빠진 재료 추가" /><button class="primary">추가</button></div>
    </div>`,
});

const suggestions = () => shell({
  body: `
    <button class="text-button retry-link">다른 사진으로 다시</button>
    <div class="card summary-card"><span class="grow subhead muted">냉장고에 있는 것 6개</span>${icon('expand')}</div>
    <div class="spacer-24"></div>
    <h3 class="large-title">오늘 할 3개</h3>
    <div class="spacer-12"></div>
    <article class="card suggestion-card" data-go="detail">
      <div class="food-photo">
        <img src="https://images.unsplash.com/photo-1590301157890-4810ed352733?w=720&q=74&auto=format&fit=crop" alt="두부김치 레시피 대표 이미지" />
        <span class="match-badge"><span class="numeric">1위 · 96%</span> 일치</span>
      </div>
      <div class="suggestion-body">
        <div class="between"><strong class="title">두부김치</strong><span class="badge go">${icon('check')}바로 가능</span></div>
        <div class="spacer-8"></div>
        <div class="source">${icon('bookmark')}<span>내 레시피 북</span></div>
        <div class="spacer-8"></div>
        <div class="subhead muted">필요한 재료가 모두 있어요.</div>
        <div class="spacer-16"></div>
        <div class="card-actions"><button class="secondary">${icon('play')} 영상 보기</button><button class="primary">이거 했어요</button></div>
      </div>
    </article>
    <div class="spacer-12"></div>
    <article class="card suggestion-card">
      <div class="food-photo">
        <img src="https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=720&q=74&auto=format&fit=crop" alt="김치볶음밥 레시피 대표 이미지" />
        <span class="match-badge"><span class="numeric">2위 · 88%</span> 일치</span>
      </div>
      <div class="suggestion-body">
        <div class="between"><strong class="title">김치볶음밥</strong><span class="badge buy">${icon('cart')}이것만 사면 가능</span></div>
        <div class="spacer-8"></div><div class="source">${icon('bookmark')}<span>내 레시피 북</span></div>
        <div class="spacer-8"></div><span class="chip">굴소스</span>
        <div class="spacer-16"></div>
        <div class="card-actions"><button class="secondary">${icon('play')} 영상 보기</button><button class="primary">이거 했어요</button></div>
      </div>
    </article>`,
});

const detail = () => `
  <div class="app-screen detail-screen">
    ${statusBar(true)}
    <div class="detail-scroll">
      <section class="detail-hero">
        <img src="https://images.unsplash.com/photo-1590301157890-4810ed352733?w=780&q=74&auto=format&fit=crop" alt="두부김치 레시피 대표 이미지" />
        <button class="circle-button" data-go="suggestions" aria-label="뒤로">${icon('back')}</button>
        <span class="video-pill">${icon('play')}영상 보기</span>
      </section>
      <section class="detail-content">
        <div class="between"><h3 class="large-title">두부김치</h3><span class="badge go">${icon('check')}바로 가능</span></div>
        <div class="spacer-8"></div>
        <div class="source">${icon('bookmark')}<span>내 레시피 북 · <span class="numeric">96%</span> 일치</span></div>
        <div class="spacer-12"></div>
        <div class="subhead muted">필요한 재료가 모두 있어요.</div>
        <div class="spacer-24"></div>
        <div class="section-label headline">있는 재료 · <span class="numeric">5</span></div>
        <div class="group">
          ${['두부', '김치', '대파', '양파', '간장'].map((name) => `<div class="ingredient-row"><span class="have-icon">${icon('check')}</span><span>${name}</span></div>`).join('')}
        </div>
        <div class="spacer-20"></div>
        <div class="section-label headline">부족 재료 · <span class="numeric">1</span></div>
        <div class="group"><div class="ingredient-row"><span class="circle-empty"></span><span class="grow">돼지고기 (앞다리)</span><span class="decorative-cart">${icon('cart')}담기</span></div></div>
        <div class="spacer-8"></div><div class="footnote muted">쿠팡·마켓컬리에서 담을 수 있어요.</div>
      </section>
    </div>
    <div class="detail-cta"><button class="primary wide" data-go="suggestions">이거 했어요</button></div>
    <div class="gesture-area"></div>
  </div>`;

const recipeRow = (title, meta, src) => `
  <div class="recipe-row">
    <img class="recipe-thumb" src="${src}" alt="${title} 레시피 대표 이미지" />
    <div class="grow"><div class="headline">${title}</div><div class="recipe-meta">${meta}</div></div>
    <button class="remove" aria-label="${title} 삭제">${icon('close')}</button>
  </div>`;

const recipeBook = () => shell({
  active: 'recipe-book',
  title: '레시피 북',
  action: '',
  body: `
    <section class="card quota">
      <div class="between"><div><strong>3 / 30</strong> <span class="headline">저장됨</span></div><span class="free-badge">무료</span></div>
      <div class="spacer-12"></div><div class="progress"><span style="width:10%"></span></div>
      <div class="spacer-8"></div><div class="footnote muted"><span class="numeric">27개</span> 더 저장할 수 있어요　<span style="color:var(--action);font-weight:600">프리미엄으로 무제한</span></div>
    </section>
    <div class="spacer-20"></div>
    <section class="recipe-form">
      <input class="field" placeholder="레시피 링크 붙여넣기" />
      <input class="field" placeholder="무슨 요리인가요? (예: 김치찌개)" />
      <button class="primary wide">레시피 북에 담기</button>
      <div class="form-caption">제목으로 재료를 짐작해 둡니다. 영상 내용은 가져오지 않아요.</div>
    </section>
    <div class="spacer-24"></div>
    <div class="section-label">저장한 레시피 · <span class="numeric">3</span></div>
    <section class="group">
      ${recipeRow('두부김치', '유튜브 · 두부 · 김치 · 대파 · 양파', 'https://images.unsplash.com/photo-1590301157890-4810ed352733?w=120&h=120&fit=crop&q=70')}
      ${recipeRow('김치볶음밥', '블로그 · 밥 · 김치 · 계란 · 대파', 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=120&h=120&fit=crop&q=70')}
      ${recipeRow('애호박전', '유튜브 · 애호박 · 계란 · 부침가루', 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=120&h=120&fit=crop&q=70')}
    </section>`,
});

const renderers = { onboarding, recognition, checklist, suggestions, detail, 'recipe-book': recipeBook };
const params = new URLSearchParams(window.location.search);
let currentIndex = Math.max(0, screens.findIndex((screen) => screen.key === params.get('screen')));

const originalFrame = document.querySelector('#original-frame');
const baselineFrame = document.querySelector('#baseline-frame');

function prepareOriginal() {
  const doc = originalFrame.contentDocument;
  if (!doc) return;
  const style = doc.createElement('style');
  style.textContent = `
    html, body { width: 414px !important; height: 868px !important; overflow: hidden !important; }
    .stage { min-height: 0 !important; width: 414px !important; height: 868px !important; padding: 0 !important; background: transparent !important; }
    .device { box-shadow: none !important; }
  `;
  doc.head.appendChild(style);
}

function goTo(index) {
  currentIndex = (index + screens.length) % screens.length;
  const screen = screens[currentIndex];
  const nextParams = new URLSearchParams(window.location.search);
  nextParams.set('screen', screen.key);
  window.history.replaceState({}, '', `${window.location.pathname}?${nextParams}`);

  document.querySelector('#screen-number').textContent = screen.number;
  document.querySelector('#screen-title').textContent = screen.title;
  document.querySelector('#screen-contract').textContent = screen.contract;
  document.querySelector('#switcher-label').textContent = `${screen.number} / 06 — ${screen.title}`;
  document.querySelector('#review-points').innerHTML = screen.review.map((point) => `<li>${point}</li>`).join('');

  originalFrame.onload = prepareOriginal;
  originalFrame.src = screen.original;
  baselineFrame.innerHTML = renderers[screen.key]();
}

function goToKey(key) {
  const index = screens.findIndex((screen) => screen.key === key);
  if (index >= 0) goTo(index);
}

document.querySelector('#previous-screen').addEventListener('click', () => goTo(currentIndex - 1));
document.querySelector('#next-screen').addEventListener('click', () => goTo(currentIndex + 1));
document.addEventListener('keydown', (event) => {
  if (['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName) || document.activeElement?.isContentEditable) return;
  if (event.key === 'ArrowLeft') goTo(currentIndex - 1);
  if (event.key === 'ArrowRight') goTo(currentIndex + 1);
});
baselineFrame.addEventListener('click', (event) => {
  const target = event.target.closest('[data-go]');
  if (target) goToKey(target.dataset.go);
});

goTo(currentIndex);
