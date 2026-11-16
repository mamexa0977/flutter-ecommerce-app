# MovieBox Flutter app (v0.1 – core features)

Search, browse (Home / Movies / Anime / Western / Asian / Kids), title details
(cast, seasons & episodes, audio versions) and playback — all through your
FastAPI backend (`moviebox_api_server.py`).

**Stack:** flutter_riverpod · dio · go_router · cached_network_image ·
shared_preferences · media_kit (libmpv: HLS, DASH, HEVC, custom headers).

## 1. Create the platform folders, then drop in this code

```bash
flutter create --org com.example --project-name moviebox_app --platforms=android,ios moviebox_app
cd moviebox_app
# copy this archive's  lib/  and  pubspec.yaml  over the generated ones
flutter pub get
```

## 2. Android permissions  (`android/app/src/main/AndroidManifest.xml`)

Inside `<manifest>` (above `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

On the `<application ...>` tag add (needed because the local backend is plain http):

```xml
android:usesCleartextTraffic="true"
```

media_kit needs minSdk 21 (Flutter's default already is).

**iOS** (`ios/Runner/Info.plist`) – allow http to your LAN backend:

```xml
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

## 3. Run the backend so the phone can reach it

```bash
python moviebox_api_server.py          # listens on 0.0.0.0:8000
```

| Where the app runs | Backend URL to use (Settings screen) |
|---|---|
| Android emulator | `http://10.0.2.2:8000` (default) |
| Real phone, same Wi-Fi | `http://<your-PC-LAN-IP>:8000` (allow port 8000 in Windows Firewall) |
| Deployed (Render etc.) | `https://your-service.onrender.com` |

## 4. Run

```bash
flutter run
```

## Project layout

```
lib/
  main.dart / app.dart        entry + router + theme
  core/api_client.dart        dio client, X-Session-Id handling, typed endpoints
  core/providers.dart         Riverpod providers
  models/models.dart          tolerant JSON models
  features/home|search|detail|player|settings
  widgets/common.dart         Poster, MovieCard, ErrorView
```

## Not included yet (backend already supports them)
login/register, watchlist, history & resume position, downloads, rankings,
community rooms/posts, sports, subtitle search, quality picker.
