# Telegram Downloader

A modern, unofficial Telegram client for Android focused strictly on **advanced file downloading**.

## Tech Stack

| Layer            | Technology                         |
| ---------------- | ---------------------------------- |
| Framework        | Flutter (Android)                  |
| Telegram Engine  | `tdlib` (Dart FFI / MTProto)       |
| State Management | Riverpod                           |
| CI/CD            | GitHub Actions → Release APK       |

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.22.0
- Dart SDK ≥ 3.4.0
- Android SDK (API 21+)
- Telegram API credentials from [my.telegram.org/apps](https://my.telegram.org/apps)

### Setup

1. **Clone the repo**
   ```bash
   git clone https://github.com/<your-org>/telegram_downloader.git
   cd telegram_downloader
   ```

2. **Add your Telegram API credentials**  
   Edit `lib/core/constants/app_constants.dart`:
   ```dart
   static const int telegramApiId = YOUR_API_ID;
   static const String telegramApiHash = 'YOUR_API_HASH';
   ```

3. **Install dependencies**
   ```bash
   flutter pub get
   ```

4. **Run on a connected device / emulator**
   ```bash
   flutter run
   ```

## CI/CD (GitHub Actions)

The workflow at `.github/workflows/build.yml` builds a signed release APK on every push to `main`.

### Required GitHub Secrets

| Secret              | Description                                      |
| ------------------- | ------------------------------------------------ |
| `KEYSTORE_BASE64`   | Base64-encoded `.jks` keystore file               |
| `KEYSTORE_PASSWORD` | Keystore password                                 |
| `KEY_ALIAS`         | Signing key alias                                 |
| `KEY_PASSWORD`      | Signing key password                              |

**Generate keystore base64:**
```bash
base64 -w 0 your-keystore.jks
```

## Project Structure

```
lib/
├── main.dart                    # Entry point — initializes TDLib
├── app.dart                     # Root MaterialApp widget
├── core/
│   ├── constants/               # App-wide constants & API keys
│   ├── tdlib/                   # TDLib client wrapper & Riverpod providers
│   ├── router/                  # Navigation / routing setup
│   └── utils/                   # Logger, helpers
├── features/
│   ├── auth/                    # Telegram authentication flow
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   ├── chat_list/               # Chat/channel listing for downloads
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   ├── downloads/               # Download queue, progress, management
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   └── settings/                # App preferences & configuration
│       ├── data/
│       ├── domain/
│       └── presentation/
└── shared/
    ├── widgets/                 # Reusable UI components
    └── models/                  # Shared data models
```

## License

This project is for personal/educational use. Not affiliated with Telegram.
