# Google Drive setup (only if you build Bubblecast yourself)

Official releases already include a Google client: users just click **Connect Google Drive** and **Allow**. You need this guide only for your own build, because Google requires every app that uses Drive to have its own OAuth client, and the client file is never stored in this repository.

1. Open <https://console.cloud.google.com/> and sign in.
2. Create a project: project menu → **New project** → name it `Bubblecast` → **Create**, then select it.
3. **APIs & Services → Library** → search **Google Drive API** → **Enable**.
4. **APIs & Services → OAuth consent screen** (Google Auth Platform):
   - App name `Bubblecast`, your email as support and developer contact.
   - Audience: **External**.
   - Data access / scopes: add `https://www.googleapis.com/auth/drive.file` (listed by Google as non-sensitive).
   - Optional: publish the app (**Audience → Publish app**, needs a homepage and privacy policy URL). While it stays in *Testing*, Google ends the sign-in after 7 days.
5. **APIs & Services → Credentials → Create credentials → OAuth client ID** → Application type **Desktop app** → name `Bubblecast Mac` → **Create**.
6. **Download JSON**. Keep it outside the repo.
7. In Bubblecast: Library → **Connect Google Drive** → choose that JSON once. Bubblecast stores it in the macOS Keychain, then opens Google sign-in. Give the same file to anyone else who should use your client.

Optional, for a private build only: save the JSON as `Config/google-client.json` (ignored by git) and run `bash scripts/release.sh`; the client is then built into that installer. Never publish such an installer.

**Testing or production?** To publish (step 4) Google asks for a homepage and a privacy policy URL. Until then the app stays in *Testing*: add every Google account that will connect under **Audience → Test users** (up to 100), and expect to click **Connect** again every 7 days.

Desktop apps cannot keep a client secret truly secret (Google treats them as public clients), which is why the sign-in also uses PKCE. Keep the JSON out of public repositories anyway.
