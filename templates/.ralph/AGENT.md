# Agent Instructions

프로젝트의 빌드, 테스트, 린트 명령을 정의합니다.
`/wi:init` 실행 시 프로젝트 타입에 맞게 자동 생성됩니다.

## 빌드 & 검증 명령

### Lint
```bash
# 프로젝트 타입에 따라 자동 설정됨
# 예: npm run lint / ruff check . / cargo clippy
```

### Build
```bash
# 예: npm run build / python -m build / cargo build
```

### Test
```bash
# 예: npm test / pytest / cargo test
```

### Type Check
```bash
# 예: npx tsc --noEmit / mypy . / (cargo build에 포함)
```

## 의존성 설치
```bash
# 예: npm install / pip install -r requirements.txt / cargo fetch
```

## 프로젝트 구조
```
# /wi:init 시 프로젝트 구조가 여기에 기록됩니다
```
