# WI System - UTF-8 Encoding Rules

Windows 환경에서 한글이 깨지지 않도록 하는 필수 규칙입니다.

## 1. 셸 스크립트
- 모든 .sh 파일 시작부에 UTF-8 환경변수 설정 필수:
  ```
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  export PYTHONUTF8=1
  export PYTHONIOENCODING=utf-8
  ```
- Windows(Git Bash/MSYS2) 감지 시 `chcp.com 65001` 실행

## 2. Git 설정
- `core.quotepath = false` (한글 파일명 정상 표시)
- `i18n.commitEncoding = utf-8`
- `i18n.logOutputEncoding = utf-8`
- `gui.encoding = utf-8`

## 3. 파일 인코딩
- 모든 텍스트 파일: UTF-8 (BOM 없음)
- 줄바꿈: LF (`.gitattributes`로 강제)
- `.editorconfig`에 `charset = utf-8` 명시

## 4. Python
- `PYTHONUTF8=1` 환경변수 설정 또는
- 스크립트 내 `sys.stdout.reconfigure(encoding='utf-8')` 호출
- 설정 없이 실행 시 cp949 인코딩으로 한글 깨짐
- Python 3.15+에서는 UTF-8이 기본값 (PEP 686). 3.14 이하에서는 반드시 위 설정 필요
- `open()` 호출 시 `encoding='utf-8'` 명시 권장 (PEP 597 경고 대응)
