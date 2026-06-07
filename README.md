# Android WebView App Template

This is a simple Android application that loads a website into a WebView. It includes a Splash Screen and a Main Activity that handles the web browsing experience.

## Getting Started

1.  **Open in Android Studio**:
    - Open Android Studio.
    - Select "Open an existing Android Studio project".
    - Navigate to this folder and click "Open".
2.  **Run the App**:
    - Connect your Android device or start an Emulator.
    - Click the green "Run" button (Play icon) in the toolbar.

---

## Configuration & Customization

You can easily customize the app by modifying a few files.

### 1. Change Website URL

To change the website that loads in the app:

1.  Open `app/src/main/res/values/strings.xml`.
2.  Change the value of `website_url`.
    ```xml
    <string name="website_url">https://www.yourwebsite.com/</string>
    ```

### 2. Change App Name

To change the name of the app as it appears on the phone:

1.  Open `app/src/main/res/values/strings.xml`.
2.  Change the value of `app_name`.
    ```xml
    <string name="app_name">Your App Name</string>
    ```

### 3. Change App Icon (Logo)

The main logo file is located at `app/src/main/res/drawable/logo.png`.

**To update the app icon:**

1.  Replace `app/src/main/res/drawable/logo.png` with your new logo file (ensure it is a PNG).
2.  For the launcher icon (the icon on the home screen), you should use the **Image Asset Studio**:
    - Right-click on the `app` folder in Android Studio.
    - Go to **New** > **Image Asset**.
    - Select your new logo image in the "Path" field.
    - Adjust the scaling and background.
    - Click **Next** and then **Finish**.

### 4. Change Colors

To change the app's theme colors (toolbar, status bar, etc.):

1.  Open `app/src/main/res/values/colors.xml`.
2.  Update the hex codes for the colors.
    - `purple_500`: The primary color of the app (Toolbar).
    - `brand_color`: Used for specific branding elements.
    - `black` / `white`: Standard colors.

Example:

```xml
<color name="purple_500">#E91E63</color> <!-- Change to your brand color -->
```

### 5. Customize "No Internet" Screen

The app shows a custom screen when there is no internet connection.

- **Icon**: The icon is located at `app/src/main/res/drawable/ic_wifi_off.xml`. You can replace `ic_wifi_off.xml` with another vector drawable.
- **Message**: To change the text "No Internet Connection" or the error message, update the strings in `activity_main.xml` (or ideally, extract them to `strings.xml`).
- **Layout**: You can modify the design in `app/src/main/res/layout/activity_main.xml` inside the `RelativeLayout` with ID `layoutError`.
