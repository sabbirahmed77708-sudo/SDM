# SDM – ডাউনলোড ম্যানেজার (Flutter)

**ফিচার**
- যেকোনো ফাইল-লিংক থেকে ডাউনলোড (ভিডিও, মিউজিক, zip, apk, pdf ইত্যাদি)
- মাল্টি-সেগমেন্ট: সার্ভার Range সাপোর্ট করলে ফাইল ৪ ভাগে একসাথে নামে (দ্রুত স্পিড)
- পজ / রিজিউম, অ্যাপ বন্ধ করে আবার খুললেও চালিয়ে নেওয়া যায়
- লাইভ স্পিড ও বাকি সময় (ETA)
- **ব্যাকগ্রাউন্ড ডাউনলোড**: অ্যাপ ব্যাকগ্রাউন্ডে থাকুক বা বন্ধ করে দিন, ডাউনলোড চলতে থাকে
- **নোটিফিকেশন বার**: প্রতিটি ডাউনলোডের আলাদা নোটিফিকেশন (কত %, কত MB / মোট MB, স্পিড) আর আলাদা Pause / Resume বোতাম; একাধিক ডাউনলোড থাকলে ওপরে Pause all / Resume all
- বিল্ট-ইন ব্রাউজার: ফাইল-লিংকে চাপলে ডাউনলোডের প্রস্তাব দেয়
- উপরে ব্রাউজার আইকন ও থ্রি-ডট মেনু (শেয়ার অ্যাপ, সেটিংস, About)
- **Share app**: অ্যাপের APK যে কারো সাথে শেয়ার করা যায়
- **About**: লোগো, ভার্সন, ডেভেলপার (SH), "Check for update" (নতুন আপডেট এলে মেনুতে ডট দেখায়)
- ডার্ক / লাইট থিম, বাংলা / ইংরেজি ভাষা
- ফাইল সেভ হয় `Download/FastGet` ফোল্ডারে; ডাউনলোডের পপআপ বা সেটিংস থেকে অন্য ফোল্ডার বাছা যায়
- ডাউনলোড পপআপ নিচ থেকে ভেসে ওঠে: নাম (বদলানো যায়), ধরন, সাইজ, লিংক, সেভ ফোল্ডার
- ডাউনলোড লিস্ট ও ব্রাউজার হিস্টোরিতে লং-প্রেস করে এক বা একাধিক ডিলিট; হিস্টোরিতে সাইটের আইকন
- Chrome-এর মতো নিচে টেনে রিফ্রেশ (হোম, ব্রাউজার)
- **Settings → Notification settings**: অনুমতি, অগ্রগতি/স্পিড/বাকি সময়, আলাদা নোটিফিকেশন, Pause/Resume বোতাম, শেষ/ব্যর্থ নোটিফিকেশন, সাউন্ড, ভাইব্রেট, পপ-আপ, লক স্ক্রিন, টেস্ট

## APK বানানোর উপায় (Android Studio ছাড়াই)

1. এই প্রজেক্টের সব ফাইল GitHub রিপোজিটরিতে আপলোড করুন (`.github` ফোল্ডারসহ)।
2. রিপোজিটরির **Actions** ট্যাবে "Build APK" নিজে থেকে চলবে (না চললে **Run workflow** চাপুন)।
3. ৫-১০ মিনিট পর **Releases** পেজে নতুন build (`DROM.apk`) পাবেন। Actions run-এর Artifacts থেকেও নামানো যায়।
4. APK ফোনে ইনস্টল করুন (Unknown sources অনুমতি দিতে হবে)।

প্রতিটি push-এ একটি করে নতুন Release হয়। অ্যাপের **About → Check for update** সেই Release দেখে নতুন ভার্সন আছে কিনা জানায়, আর সেখান থেকেই ডাউনলোড করা যায়।

> সব build একই সাইনিং কি (`tool/debug.keystore`) দিয়ে সাইন হয়, তাই নতুন APK পুরোনোটার ওপর ইনস্টল হয়ে যায় (আনইনস্টল লাগে না)।

## প্রথমবার চালানোর সময়
- "সব ফাইল অ্যাক্সেস" (All files access) অনুমতি চাইবে। দিলে ফাইল `Download/FastGet`-এ যাবে; না দিলে অ্যাপের নিজস্ব ফোল্ডারে সেভ হবে।
- নোটিফিকেশনের অনুমতি দিন, নইলে ডাউনলোডের % নোটিফিকেশন বারে দেখা যাবে না।

## নোট
- সার্ভার Range সাপোর্ট না করলে সিঙ্গেল স্ট্রিমে নামে (রিজিউম হবে না)।
- কিছু ফোনে (Xiaomi, Oppo, Vivo, Samsung ইত্যাদি) ব্যাটারি সেভার ব্যাকগ্রাউন্ড অ্যাপ বন্ধ করে দেয়। SDM-এর ব্যাটারি সেটিং "Unrestricted / No restrictions" করে দিন।
- সব ধরনের কনটেন্ট ডাউনলোডের অনুমতি আছে।

## লোকাল বিল্ড (Flutter SDK থাকলে)
```bash
flutter create --platforms=android --org com.fastget --project-name fastget .
python3 tool/patch_manifest.py
mkdir -p ~/.android && cp tool/debug.keystore ~/.android/debug.keystore
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release
```

## Share and copy links
- From any app, use **Share → SDM** on a file link and SDM shows the download prompt.
- Copy a direct file link, then open SDM: it offers to download it.
- Every link is checked first; web pages are refused, and YouTube links are not supported.

## Project layout
- `lib/download_manager.dart` – download engine (segments, pause/resume, Wi-Fi only)
- `lib/notifier.dart` + `tool/DownloadService.kt.tpl` – notification and foreground service
- `tool/MainActivity.kt.tpl` – keeps the Flutter engine alive after the app is closed
- `lib/updater.dart` – update check against GitHub Releases
- `assets/icon/logo.png` – the SDM logo; `tool/make_icon.py` builds the launcher icons from it
