# API Standard Contract

프론트엔드 ↔ 백엔드 간 API 응답 형식 합의.
이 파일은 `/wi:start`에서 프로젝트 타입에 맞게 자동 채워집니다.

## 응답 형식
```json
{
  "success": true,
  "data": {},
  "error": null,
  "meta": {
    "page": 1,
    "limit": 20,
    "total": 100
  }
}
```

## 에러 형식
```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "입력값이 올바르지 않습니다",
    "details": []
  }
}
```

## HTTP 상태 코드
| 코드 | 용도 |
|------|------|
| 200 | 성공 (조회, 수정) |
| 201 | 생성 성공 |
| 400 | 클라이언트 에러 (유효성 검증 실패) |
| 401 | 인증 필요 |
| 403 | 권한 없음 |
| 404 | 리소스 없음 |
| 500 | 서버 에러 |

## 엔드포인트 네이밍
- RESTful: `GET /api/{resource}`, `POST /api/{resource}`, `PATCH /api/{resource}/:id`
- 목록 조회는 페이지네이션 필수 (`?page=1&limit=20`)

## 변경 규칙
- 이 파일 수정 시 프론트엔드 + 백엔드 팀 모두 확인 필수
- 기존 필드 삭제/변경은 deprecation 기간 (1 sprint) 후 제거
