# Roblox GPT Bridge

## Multi-user distribution

Do not give every user the shared server key. Each Studio installation must press **Create Pairing Code** and give the 12-character code to the configured GPT. The GPT calls `pairRobloxStudio`, receives a `deviceId`, and includes it in every command. The server then isolates commands by device and authenticates the plugin with a device-specific token.

### Render deployment

1. Push this directory to a private Git repository.
2. Create a Render Blueprint from `render.yaml`.
3. Set `PUBLIC_BASE_URL` to the generated HTTPS service URL.
4. Put Render's generated `BRIDGE_API_KEY` into the GPT Action Bearer authentication field.
5. Import `https://YOUR-SERVICE/openapi.json` as the Action schema.
6. Replace the placeholders in `PRIVACY.md` and `TERMS.md`, then publish both pages before public GPT sharing.

The included command/device store is single-process and in-memory. It is suitable for a small private beta. Replace it with Redis or PostgreSQL before running multiple server instances or launching a paid public service.

ChatGPT의 커스텀 GPT Action과 Roblox Studio 플러그인을 연결하는 개인용 MVP입니다.

## 제공 기능

- Explorer 트리 조회와 인스턴스 검색
- 속성 및 Attribute 조회
- Part, Model, Script와 주요 GUI 클래스 생성
- 인스턴스 복제·이동·이름 변경·일괄 생성
- 인스턴스 속성과 Attribute 변경
- 중첩 GUI 트리와 WeldConstraint 생성
- GUI를 런타임 생성 스크립트 없이 실제 Studio 인스턴스로 직접 제작
- 선택 항목 조회·변경, 모델 Pivot·Scale 편집
- 프로젝트 전체 코드 검색과 스크립트 부분 패치
- Studio Output 로그 수집 및 오류 분석
- CollectionService 태그와 물리 Constraint 관리
- 최대 50개 작업을 하나의 승인 및 Undo 기록으로 실행
- Terrain 블록·구체 생성과 영역 제거
- Studio 편집 카메라 위치 변경
- Instance 참조 속성과 ColorSequence·NumberSequence 등 고급 속성 지원
- Lua 스크립트 소스 변경
- 인스턴스 삭제
- Studio에서 변경 명령 승인 또는 거절
- Studio Undo/Redo 기록
- Bearer/API 키 인증과 명령 허용 목록

## 1. 키 생성 및 서버 실행

PowerShell에서 프로젝트 폴더로 이동한 다음 충분히 긴 임의 키를 설정합니다.

```powershell
cd C:\Users\user\roblox-gpt-bridge
$env:BRIDGE_API_KEY = "여기에-긴-임의-문자열"
npm start
```

브라우저에서 `http://127.0.0.1:8787/health`를 열어 `{"ok":true}`가 나오는지 확인합니다.

## 2. Roblox Studio 플러그인 설치

1. Roblox Studio에서 새 프로젝트를 엽니다.
2. `ServerStorage`에 `Script`를 만들고 `plugin/RobloxGPTBridge.server.lua` 내용을 붙여넣습니다.
3. 스크립트를 선택한 뒤 **Plugins → Save as Local Plugin**을 선택합니다.
4. 원본 `ServerStorage` 스크립트는 삭제합니다.
5. **Home → Game Settings → Security → Allow HTTP Requests**를 켭니다.
6. Plugins 탭에서 **GPT Bridge**를 누릅니다.
7. URL은 로컬 테스트 시 `http://127.0.0.1:8787`, Shared key는 서버의 `BRIDGE_API_KEY`와 동일하게 입력하고 Connect를 누릅니다.

키는 Studio의 로컬 플러그인 설정에 저장됩니다. 공용 컴퓨터에서는 사용하지 마세요.

## 3. ChatGPT가 접근할 HTTPS 주소 만들기

ChatGPT Action은 로컬 주소에 접근하지 못하므로 서버에 공개 HTTPS 주소가 필요합니다. 서버를 신뢰할 수 있는 호스팅에 배포하거나 Cloudflare Tunnel 같은 HTTPS 터널을 사용하세요.

공개 주소가 `https://bridge.example.com`이라면 서버 시작 전에 다음 값도 설정합니다.

```powershell
$env:PUBLIC_BASE_URL = "https://bridge.example.com"
$env:BRIDGE_API_KEY = "Studio와-같은-긴-키"
npm start
```

공개 URL과 키를 타인에게 공개하지 마세요. 서버는 기본적으로 `127.0.0.1`에만 바인딩됩니다.

## 4. 커스텀 GPT 만들기

1. `https://chatgpt.com/gpts/editor`에서 GPT를 만듭니다.
2. 지침에 `GPT_INSTRUCTIONS.md` 내용을 붙여넣습니다.
3. **Configure → Actions → Create new action**으로 이동합니다.
4. Authentication은 **API Key → Bearer**를 선택하고 `BRIDGE_API_KEY` 값을 입력합니다.
5. Schema에서 `https://공개주소/openapi.json`을 가져오거나 그 내용을 붙여넣습니다.
6. Action을 지원하는 모델을 선택합니다. 채팅의 **Pro mode**에서는 Action이 비활성화될 수 있습니다.
7. GPT는 우선 **Only me**로 저장하고 Preview에서 시험합니다.

첫 시험 명령:

> 현재 Workspace 구조를 확인해 줘.

두 번째 시험 명령:

> Workspace에 이름이 GPTPart인 빨간색 Part를 만들고 크기를 10, 1, 10으로 설정해 줘.

변경 명령이 도착하면 Studio의 GPT Bridge 창에서 내용을 확인하고 **Approve**를 눌러야 실행됩니다. 조회 명령은 자동으로 실행됩니다.

## Action 인수 예시

```json
{
  "action": "create_instance",
  "args": {
    "parentPath": "Workspace",
    "className": "Part",
    "name": "GPTPart",
    "properties": {
      "Size": [10, 1, 10],
      "Color": [255, 0, 0],
      "Anchored": true
    }
  }
}
```

## 보안 제한

- 허용되지 않은 클래스는 생성하지 않습니다.
- `Parent`와 `Source`는 일반 속성 변경으로 수정할 수 없습니다.
- 서비스와 DataModel은 삭제할 수 없습니다.
- 모든 변경은 Studio 승인 버튼을 거치며, 삭제 및 스크립트 소스 변경은 채팅에서도 확인하도록 구성되어 있습니다.
- 외부에 배포한다면 TLS, 속도 제한, 영속 저장소, 사용자별 인증을 추가해야 합니다.
