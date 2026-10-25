/* 기본 내장 팩: 동아시아사
 * 이 폴더의 다른 파일(korea-1.js 등)이 HT.extendPack으로 시대·사건을 채웁니다.
 * 연도: 음수 = 기원전. 고대의 건국 연도 등은 사료의 전승을 따른 것이 있습니다. */
HT.definePack({
  id: 'east-asia-base',
  name: '동아시아사 기본팩',
  version: '1.0.0',
  author: '역사 연표',
  description: '한국·중국·일본·베트남의 주요 시대와 사건 (북방 유목 정권은 중국 트랙 안에 함께 놓입니다)',
  /* 문화권(트랙 위의 층 — DLC-형식.md 'spheres'): 프로그램에 든 문화권은 없어 동아시아도 이 팩이 만듭니다(2026-10-23). 다른 DLC의 동아시아 트랙은 sphere: 'east-asia'로 */
  spheres: [{ id: 'east-asia', name: '동아시아', order: 1 }],
  tracks: [
    { id: 'korea', name: '한국', color: '#5b7fbd', order: 10, sphere: 'east-asia' },
    { id: 'china', name: '중국', color: '#b8634f', order: 20, sphere: 'east-asia' },
    { id: 'japan', name: '일본', color: '#9a7bb0', order: 30, sphere: 'east-asia' },
    { id: 'vietnam', name: '베트남', color: '#4f9a78', order: 40, sphere: 'east-asia' },
  ],
  categories: [],
  /* 민족 계층: parent가 대명제. 정권(relations.js)은 어느 단계에든 붙습니다. */
  peoples: [
    { id: 'korean', name: '한민족', color: '#5b7fbd', order: 1 },
    { id: 'yemaek', name: '예맥', parent: '한민족', order: 1 },
    { id: 'samhan', name: '한(삼한)', parent: '한민족', order: 2 },

    { id: 'hanzu', name: '한족', color: '#b8634f', order: 1 },
    { id: 'wuhu', name: '오호', description: '5호 16국 시대의 다섯 이민족', order: 2 },
    { id: 'xiongnu', name: '흉노족', parent: '오호', order: 1 },
    { id: 'di', name: '저족', parent: '오호', order: 2 },
    { id: 'qiang', name: '강족', parent: '오호', order: 3 },
    { id: 'jie', name: '갈족', parent: '오호', order: 4 },
    { id: 'xianbei', name: '선비족', parent: '오호', order: 5 },
    { id: 'early-nomads', name: '초기 유력 이민족', order: 3 },
    { id: 'rouran', name: '유연', parent: '초기 유력 이민족', order: 1 },
    { id: 'turk', name: '돌궐족', parent: '초기 유력 이민족', order: 2 },
    { id: 'uyghur', name: '위구르족', parent: '초기 유력 이민족', order: 3 },
    { id: 'late-nomads', name: '후기 유력 이민족', order: 4 },
    { id: 'shatuo', name: '사타족', parent: '후기 유력 이민족', order: 1 },
    { id: 'khitan', name: '거란족', parent: '후기 유력 이민족', order: 2 },
    { id: 'mongolic', name: '몽골계', parent: '후기 유력 이민족', order: 3 },
    { id: 'mongol', name: '몽골족', parent: '몽골계', description: '몽골 제국·원·북원의 몽골', order: 1 },
    { id: 'jurchen', name: '여진-만주족', parent: '후기 유력 이민족', order: 4 },
    { id: 'tibetan', name: '티베트족', parent: '후기 유력 이민족', order: 5 },

    { id: 'yamato', name: '야마토족', color: '#9a7bb0', order: 1 },
    { id: 'jomon', name: '조몬족', order: 2 },
    { id: 'ryukyu', name: '류큐족', order: 3 },

    { id: 'viet', name: '비엣족', color: '#4f9a78', order: 1 },
    { id: 'cham', name: '참족', order: 2 },
  ],
});
