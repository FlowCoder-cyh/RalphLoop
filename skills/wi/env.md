---
name: env
description: "인프라 환경 구성 (DB, 배포, 외부 서비스 — 대화형)"
category: workflow
complexity: advanced
mcp-servers: []
personas: [devops-engineer]
---

# /wi:env - Infrastructure Environment Setup

> PRD를 분석하여 필요한 인프라를 파악하고, 사용자와 대화하며 환경을 구성합니다.

## Triggers
- PRD 완료 후, `/wi:start` 실행 전
- 인프라 환경 구성 요청

## Usage
```
/wi:env [prd-file-path]
```
기본값: `./PRD.md`

## Prerequisites
- `/wi:prd`로 PRD가 생성된 상태
- `/wi:init`으로 프로젝트 초기 환경이 셋업된 상태

## Behavioral Flow

### Phase 1: PRD 분석 → 인프라 요구사항 파악

PRD에서 필요한 인프라를 자동으로 추출합니다:

**분석 대상:**
| 카테고리 | 키워드/패턴 | 인프라 매핑 |
|---------|-----------|-----------|
| 데이터베이스 | PostgreSQL, MySQL, MongoDB, Prisma, 스키마 | Supabase, PlanetScale, MongoDB Atlas |
| 배포 | Next.js, Vercel, AWS, 배포 | Vercel CLI, AWS CLI |
| 인증 | NextAuth, OAuth, SSO, 로그인 | NextAuth provider credentials |
| 결제 | 결제, 구독, 빌링 | Stripe |
| 이메일 | 이메일, 알림, 발송 | Resend, SendGrid |
| 파일 저장 | 업로드, 파일, 이미지 | S3, Cloudflare R2 |
| 실시간 | WebSocket, 실시간, 채팅 | Pusher, LiveKit |
| 모니터링 | 에러 추적, 모니터링 | Sentry |
| 검색 | 전문 검색, 검색 엔진 | Algolia, Meilisearch |

**출력:**
```
📋 PRD 분석 결과 — 필요한 인프라:

필수:
  1. 데이터베이스: PostgreSQL (Prisma ORM)
     → 권장: Supabase (무료 티어 가용)
  2. 배포: Next.js App Router
     → 권장: Vercel (Next.js 최적화)
  3. 인증: NextAuth.js (Google, Microsoft OAuth)
     → 필요: OAuth provider credentials

선택:
  4. 이메일: 알림 발송
     → 권장: Resend (무료 100건/일)

추가하거나 빼고 싶은 항목이 있나요?
```

### Phase 2: MCP/CLI 설치

사용자 확인 후, 필요한 도구를 설치합니다:

```bash
# MCP 서버 설치 (프로젝트 스코프)
claude mcp add --scope project --transport stdio supabase -- npx -y @supabase/mcp-server
# 또는
npm install -g vercel  # Vercel CLI

# 설치 확인
claude mcp list
vercel --version
```

**사용자에게 설명:**
```
🔧 설치할 도구:
  1. Supabase MCP — Claude가 직접 DB를 생성하고 스키마를 적용할 수 있습니다
  2. Vercel CLI — 배포 환경 연결과 환경변수 관리에 사용합니다

설치할까요? (Y/n)
```

### Phase 3: 인프라 환경 구성 (대화형)

각 인프라를 단계별로 설명하면서 구성합니다.

#### 3-1. 데이터베이스

**Supabase 예시:**
```
📦 데이터베이스 설정 (Supabase)

1단계: Supabase 계정이 있으신가요?
  - 있으면 → 기존 프로젝트 사용 or 새 프로젝트 생성
  - 없으면 → https://supabase.com 에서 무료 가입 안내

2단계: Supabase MCP로 프로젝트 생성 또는 연결
  (MCP가 자동으로 처리합니다)

3단계: 연결 URL 획득 → .env에 자동 세팅
  DATABASE_URL="postgresql://..."
  DIRECT_URL="postgresql://..."
```

**사용자 확인:**
- 기존 프로젝트 사용 여부
- 프로젝트 이름
- 리전 (가까운 리전 자동 추천)

#### 3-2. 배포 환경

**Vercel 예시:**
```
🚀 배포 설정 (Vercel)

1단계: Vercel 계정 연결
  vercel login

2단계: 프로젝트 연결
  vercel link

3단계: 환경변수 주입
  (DB URL 등 .env 값을 Vercel에 자동 등록)
  vercel env add DATABASE_URL production
```

#### 3-3. 인증 Provider

**NextAuth 예시:**
```
🔐 인증 설정

Google OAuth:
  1. https://console.cloud.google.com 에서 OAuth 2.0 클라이언트 생성
  2. Authorized redirect URI: https://{domain}/api/auth/callback/google
  3. Client ID와 Secret을 입력해주세요:
     GOOGLE_CLIENT_ID=
     GOOGLE_CLIENT_SECRET=

(안내 링크를 따라 생성하시고, 값을 붙여넣기 해주세요)
```

#### 3-4. 외부 서비스 (PRD에서 파악된 것만)

각 서비스별 동일 패턴:
1. 계정/API 키 필요 여부 안내
2. 가입 또는 키 발급 절차 안내
3. 키 입력 → .env에 세팅

### Phase 4: .env 검증

```bash
# 필수 환경변수 누락 확인
# PRD에서 파악된 인프라 목록 기반으로 체크리스트 생성

📋 환경변수 검증:
  ✅ DATABASE_URL — 설정됨
  ✅ DIRECT_URL — 설정됨
  ✅ NEXTAUTH_SECRET — 자동 생성됨
  ✅ NEXTAUTH_URL — http://localhost:3000
  ✅ GOOGLE_CLIENT_ID — 설정됨
  ✅ GOOGLE_CLIENT_SECRET — 설정됨
  ❌ RESEND_API_KEY — 미설정 (선택 사항 — 나중에 추가 가능)
```

### Phase 5: 연결 테스트

```bash
# DB 연결 테스트
npx prisma db push --accept-data-loss 2>/dev/null && echo "✅ DB 연결 성공"

# 로컬 빌드 테스트
npm run build && echo "✅ 빌드 성공"

# 배포 프리뷰 (선택)
vercel --prod=false && echo "✅ 프리뷰 배포 성공"
```

### Phase 5.5: GitHub Secrets 등록

CI/CD(GitHub Actions)에서 E2E 테스트, DB 연결 등이 동작하려면 `.env` 값을 GitHub Secrets에 등록해야 합니다.

```bash
# .env에서 값을 읽어 GitHub Secrets에 자동 등록
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  echo "  등록: $key"
  gh secret set "$key" --body "$value"
done < .env

echo "✅ GitHub Secrets 등록 완료"
```

**사용자에게 설명:**
```
🔐 GitHub Secrets 등록

CI/CD에서 DB, 인증 등이 동작하려면 환경변수가 GitHub에도 필요합니다.
.env 파일의 값을 GitHub Secrets에 자동 등록합니다.

등록할까요? (Y/n)
```

**CI workflow 확인:**
등록 후, ci.yml과 e2e.yml에서 secrets를 env로 사용하는지 확인합니다.
워크플로우에 아래 패턴이 있어야 합니다:
```yaml
env:
  DATABASE_URL: ${{ secrets.DATABASE_URL }}
  DIRECT_URL: ${{ secrets.DIRECT_URL }}
  NEXTAUTH_SECRET: ${{ secrets.NEXTAUTH_SECRET }}
  NEXTAUTH_URL: http://localhost:3000
```
없으면 자동으로 추가합니다.

**출력:**
```
🔗 연결 테스트 + Secrets 등록 결과:
  ✅ 데이터베이스 — PostgreSQL 연결 성공
  ✅ 빌드 — Next.js 빌드 성공
  ✅ 배포 — Vercel 프리뷰 정상
  ✅ GitHub Secrets — {N}개 등록됨
  ⏭️ 이메일 — Resend 키 미설정 (나중에 추가 가능)

✅ 환경 구성 완료! 이제 /wi:start 로 개발을 시작할 수 있습니다.
```

### Phase 6: .env 보안 확인

```
⚠️ 보안 확인:
  ✅ .env는 .gitignore에 포함되어 있습니다
  ✅ .env.example 생성됨 (키 없이 변수명만, 팀원용)
  ❌ .env 파일을 절대 커밋하지 마세요
```

`.env.example` 자동 생성:
```
# Database
DATABASE_URL=
DIRECT_URL=

# Auth
NEXTAUTH_SECRET=
NEXTAUTH_URL=http://localhost:3000
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
```

## 출력 형식

```
📋 인프라 분석 완료
  - 필수: {N}개 (DB, 배포, 인증)
  - 선택: {N}개 (이메일, 모니터링)

🔧 도구 설치:
  ✅ Supabase MCP
  ✅ Vercel CLI

🔗 환경 구성:
  ✅ 데이터베이스 — Supabase ({project-name})
  ✅ 배포 — Vercel ({project-name})
  ✅ 인증 — Google OAuth
  ⏭️ 이메일 — 나중에 설정

✅ /wi:start 로 개발을 시작할 수 있습니다.
```

## Boundaries

**Will:**
- PRD에서 인프라 요구사항 자동 파악
- MCP/CLI 설치 제안 및 실행
- 사용자와 대화하며 단계별 환경 구성
- .env 생성 및 검증
- .env.example 자동 생성
- 연결 테스트 실행

**Will Not:**
- 사용자 확인 없이 유료 서비스 가입
- .env 파일을 git에 커밋
- 프로덕션 환경 직접 수정 (프리뷰만)
- 코드 구현 (그건 FlowSet이 담당)
- PRD 내용 임의 수정
