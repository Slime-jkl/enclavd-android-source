# Enclavd
<center>
<img width="2264" height="944" alt="enclavd-android" src="https://github.com/user-attachments/assets/ac709a58-21c1-4188-9f79-9a37fcec8175" />
</center>



A native Android wrapper for [enclavd.com](https://enclavd.com/?utm_source=github&utm_medium=android-app&utm_campaign=android-app-source), designed to provide a fast, secure, and seamless mobile web experience.

## Features

* **Native WebView Integration**: Persistent cookie management and optimized User-Agent handling.
* **App Links**: Full support for [enclavd.com](https://enclavd.com/?utm_source=github&utm_medium=android-app&utm_campaign=android-app-source) deep linking.
* **Media Management**: Native image downloading (saved directly to DCIM) and robust file upload support.
* **Modern UI**: Implemented with AndroidX Splash Screen API, adaptive WebP launcher icons, and Material Design bottom sheets.
* **Performance**: Lightweight architecture with automated error handling and native-feel navigation.

## Build Instructions

### Prerequisites
* Android Studio (latest stable version)
* JDK 17+
* Android SDK (Target API 34+)

### Compilation
1. Clone the repository: `git clone https://github.com/Slime-jkl/enclavd-android.git`
2. Open in Android Studio: Select the root directory.
3. Build: The project uses Gradle to manage dependencies. Once opened, sync the project and run the app configuration.

## Configuration

* **Website URL & UTMs**: Modify `app/src/main/res/values/strings.xml` to update the base URL or adjust tracking parameters.
* **Branding**: Colors are centralized in `app/src/main/res/values/colors.xml`.
* **Assets**: Launcher icons are managed as adaptive WebP assets. Use the Android Studio Image Asset Studio to update branding imagery.

## Technical Roadmap

* **Current Version**: 1.3.0
* **CI/CD**: Automated builds and integrity checks are managed via GitHub Actions (.github/workflows/android.yml).
* **Contribution Guidelines**: 
    * Maintain MainActivity.kt logic for intent filtering.
    * Ensure all new UI overlays utilize Material Design components.
    * Verify file system permissions (MediaStore) before submitting changes.

## License

This project is open-sourced under the [GPL-3.0] license. See the LICENSE file for full terms.
