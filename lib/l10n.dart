import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App language. English is the default; Bengali is selectable in the menu.
/// Strings are written in English in the code and translated through [tr].
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  String code = 'en'; // 'en' | 'bn'
  bool get isBn => code == 'bn';

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    code = p.getString('lang') ?? 'en';
  }

  Future<void> setLanguage(String c) async {
    if (c == code) return;
    code = c;
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', c);
    notifyListeners();
  }
}

/// Translate an English UI string. Unknown strings stay in English.
String tr(String en) {
  if (!L10n.instance.isBn) return en;
  return _bn[en] ?? en;
}

/// "50 MB of 1.4 GB" / "50 MB / 1.4 GB"
String trOf(String a, String b) => L10n.instance.isBn ? '$a / $b' : '$a of $b';

/// `const`-friendly translated text.
class T extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  const T(this.text,
      {super.key, this.style, this.maxLines, this.overflow, this.textAlign});

  @override
  Widget build(BuildContext context) => Text(
        tr(text),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
}

const Map<String, String> _bn = {
  "Can't open this page": 'পেজটি খোলা যাচ্ছে না',
  'checking…': 'চেক করা হচ্ছে…',
  'size unknown': 'সাইজ অজানা',
  'Wi-Fi only is on': 'শুধু ওয়াই-ফাই চালু',
  'Wi-Fi only is off': 'শুধু ওয়াই-ফাই বন্ধ',
  // --- app menu / settings / about
  'Redownload': 'আবার ডাউনলোড',
  'Wi-Fi only': 'শুধু ওয়াই-ফাই',
  'Download only when connected to Wi-Fi': 'শুধু ওয়াই-ফাই সংযোগে ডাউনলোড হবে',
  'Night mode': 'নাইট মোড',
  'Light mode': 'লাইট মোড',
  'Language': 'ভাষা',
  'Choose language': 'ভাষা বাছাই করুন',
  'About': 'সম্পর্কে',
  'Exit': 'বের হন',
  'Version': 'সংস্করণ',
  'Download folder': 'ডাউনলোড ফোল্ডার',
  'Browser settings': 'ব্রাউজার সেটিংস',
  'Downloads': 'ডাউনলোড',
  'Waiting for Wi-Fi': 'ওয়াই-ফাইয়ের অপেক্ষায়',
  'Paused': 'পজড',
  'Completed': 'সম্পন্ন',
  'Loading…': 'লোড হচ্ছে…',
  'Redownload this file?': 'ফাইলটি আবার ডাউনলোড করবেন?',
  'The partial or finished file will be deleted and downloaded again.':
      'আংশিক বা সম্পূর্ণ ফাইলটি মুছে নতুন করে ডাউনলোড হবে।',
  'Speed download manager with a built-in browser.':
      'বিল্ট-ইন ব্রাউজারসহ স্পিড ডাউনলোড ম্যানেজার।',
  // --- error messages
  'This link opens a web page, not a downloadable file':
      'এই লিংক একটি ওয়েবপেজ খোলে, ডাউনলোডযোগ্য ফাইল নয়',
  'YouTube links are not supported. Use YouTube Premium for offline videos.':
      'ইউটিউব লিংক সাপোর্ট করা হয় না। অফলাইন ভিডিওর জন্য YouTube Premium ব্যবহার করুন।',
  'No internet connection or server unreachable':
      'ইন্টারনেট সংযোগ নেই বা সার্ভারে পৌঁছানো যাচ্ছে না',
  'Connection timed out': 'সংযোগে টাইমআউট হয়েছে',
  'Unknown error': 'অজানা সমস্যা',
  // --- browser menu
  'Menu': 'মেনু',
  'Back': 'পেছনে',
  'Forward': 'সামনে',
  'Bookmark': 'বুকমার্ক',
  'Refresh': 'রিফ্রেশ',
  'Settings': 'সেটিংস',
  'New Tab': 'নতুন ট্যাব',
  'Block Ads': 'বিজ্ঞাপন ব্লক',
  'Capture Audio/Video': 'অডিও/ভিডিও ক্যাপচার',
  'View Page Resources': 'পেজ রিসোর্স দেখুন',
  'History': 'ইতিহাস',
  'Find in Page': 'পেজে খুঁজুন',
  'Desktop Mode': 'ডেস্কটপ মোড',
  'Clear Browsing Data': 'ব্রাউজিং ডেটা মুছুন',
  'Return to SDM': 'SDM-এ ফিরুন',
  'About SDM': 'SDM সম্পর্কে',
  // --- browser screen
  'Added to SDM downloads': 'SDM ডাউনলোডে যোগ হয়েছে',
  'View': 'দেখুন',
  'Search or type a URL': 'সার্চ করুন বা লিংক লিখুন',
  'Stop': 'থামান',
  'Find in page': 'পেজে খুঁজুন',
  'Previous': 'আগেরটা',
  'Next': 'পরেরটা',
  'Close': 'বন্ধ করুন',
  'New tab': 'নতুন ট্যাব',
  // --- download prompt
  'File': 'ফাইল',
  'SDM Download': 'SDM ডাউনলোড',
  'This server does not support fast multi-part download or resume.':
      'এই সার্ভার দ্রুত মাল্টি-পার্ট ডাউনলোড বা রিজিউম সাপোর্ট করে না।',
  'This link returns a web page, not a downloadable file.':
      'এই লিংক একটি ওয়েবপেজ দেখাচ্ছে, ডাউনলোডযোগ্য ফাইল নয়।',
  'Cancel': 'বাতিল',
  'Download': 'ডাউনলোড',
  // --- browser home
  'Add shortcut': 'শর্টকাট যোগ করুন',
  'Name': 'নাম',
  'Website address': 'ওয়েবসাইটের ঠিকানা',
  'Add': 'যোগ করুন',
  'Fast. Private. Yours.': 'দ্রুত। ব্যক্তিগত। আপনার।',
  'Search': 'সার্চ',
  'Remove': 'সরান',
  // --- sheets / settings
  'Page resources': 'পেজ রিসোর্স',
  'No resources were recorded for this page yet.':
      'এই পেজের কোনো রিসোর্স এখনো রেকর্ড হয়নি।',
  'Audio / video on this page': 'এই পেজের অডিও / ভিডিও',
  'No direct media files found on this page.':
      'এই পেজে সরাসরি মিডিয়া ফাইল পাওয়া যায়নি।',
  'Filter': 'ফিল্টার',
  'Link copied': 'লিংক কপি হয়েছে',
  'No app on this phone can open this file.': 'এই ফোনে এমন কোনো অ্যাপ নেই যা এই ফাইল খুলতে পারে।',
  'Allow access to files and media in the phone settings to open this file.': 'ফাইলটি খুলতে ফোনের সেটিংসে ফাইল ও মিডিয়ার অনুমতি দিন।',
  'Could not open this file.': 'ফাইলটি খোলা গেল না।',
  'File not found. It may have been deleted or moved.': 'ফাইল পাওয়া যায়নি। হয়তো মুছে গেছে বা সরানো হয়েছে।',
  'Download with SDM': 'SDM দিয়ে ডাউনলোড',
  'Clear history': 'ইতিহাস মুছুন',
  'Clear history?': 'ইতিহাস মুছবেন?',
  'Clear': 'মুছুন',
  'Bookmarks': 'বুকমার্ক',
  'No history yet': 'এখনো কোনো ইতিহাস নেই',
  'No bookmarks yet': 'এখনো কোনো বুকমার্ক নেই',
  'Block ads': 'বিজ্ঞাপন ব্লক করুন',
  'Blocks common ad and tracker domains':
      'পরিচিত বিজ্ঞাপন ও ট্র্যাকার ডোমেইন ব্লক করে',
  'Desktop mode': 'ডেস্কটপ মোড',
  'Request the desktop version of sites': 'সাইটের ডেস্কটপ সংস্করণ চান',
  'Capture audio / video': 'অডিও / ভিডিও ক্যাপচার',
  'Lists direct media files found on a page':
      'পেজে পাওয়া সরাসরি মিডিয়া ফাইলের তালিকা দেখায়',
  'Theme': 'থিম',
  'System': 'সিস্টেম',
  'Light': 'লাইট',
  'Dark': 'ডার্ক',
  'Clear browsing data': 'ব্রাউজিং ডেটা মুছুন',
  'History, cache, cookies and site data': 'ইতিহাস, ক্যাশ, কুকি ও সাইটের ডেটা',
  'Clear browsing data?': 'ব্রাউজিং ডেটা মুছবেন?',
  'This removes history, cache, cookies and saved site data. ':
      'এতে ইতিহাস, ক্যাশ, কুকি ও সংরক্ষিত সাইট ডেটা মুছে যাবে। ',
  'You will be signed out of websites.':
      'ওয়েবসাইট থেকে আপনি সাইন আউট হয়ে যাবেন।',
  'Browsing data cleared': 'ব্রাউজিং ডেটা মুছে ফেলা হয়েছে',
  'The page could not be loaded': 'পেজটি লোড করা যায়নি',
  'Try again': 'আবার চেষ্টা করুন',
  // --- tabs drawer
  'No matching tabs': 'মিলে এমন কোনো ট্যাব নেই',
  'Search tabs': 'ট্যাব খুঁজুন',
  'Tabs': 'ট্যাব',
  'Home': 'হোম',
  'Homepage': 'হোমপেজ',
  'Close tab': 'ট্যাব বন্ধ করুন',
  // --- downloads screen
  'New download': 'নতুন ডাউনলোড',
  'Paste a direct link to a file': 'ফাইলের সরাসরি লিংক পেস্ট করুন',
  'Paste': 'পেস্ট',
  'Start download': 'ডাউনলোড শুরু করুন',
  'Copy link': 'লিংক কপি',
  'Remove from list': 'তালিকা থেকে সরান',
  'Delete file too': 'ফাইলসহ মুছুন',
  'Browser': 'ব্রাউজার',
  'Add link': 'লিংক যোগ করুন',
  'Current speed': 'বর্তমান স্পিড',
  'Active': 'চলছে',
  'Done': 'শেষ',
  'All': 'সব',
  'No downloads here': 'এখানে কোনো ডাউনলোড নেই',
  'Tap "Add link" to paste a file URL,\nor use the browser to find files.':
      'ফাইলের লিংক পেস্ট করতে "লিংক যোগ করুন" চাপুন,\nঅথবা ব্রাউজার দিয়ে ফাইল খুঁজুন।',
  'Failed': 'ব্যর্থ',
  'Open': 'খুলুন',
  'Pause': 'পজ',
  'Retry': 'আবার চেষ্টা',
  'Resume': 'রিজিউম',
  'More': 'আরও',
  'Single stream · no resume': 'সিঙ্গেল স্ট্রিম · রিজিউম নেই',
  // --- share / about / update / notifications
  'Share app': 'অ্যাপ শেয়ার করুন',
  'Get SDM - a fast download manager with a built-in browser.':
      'SDM নিন - বিল্ট-ইন ব্রাউজারসহ দ্রুত ডাউনলোড ম্যানেজার।',
  'Check for update': 'আপডেট চেক করুন',
  'Our website': 'আমাদের ওয়েবসাইট',
  'Connecting…': 'সংযোগ হচ্ছে…',
  'No new update right now. You have the latest version.': 'এখন কোনো নতুন আপডেট নেই। আপনার কাছে সর্বশেষ ভার্সনই আছে।',
  'Checking for updates…': 'আপডেট চেক করা হচ্ছে…',
  'You are up to date': 'আপনার অ্যাপ সর্বশেষ ভার্সনে আছে',
  'New version available': 'নতুন আপডেট এসেছে',
  'Download update': 'আপডেট ডাউনলোড করুন',
  'Could not check for updates': 'আপডেট চেক করা যায়নি',
  'Update added to downloads. Open it when it finishes to install.':
      'আপডেট ডাউনলোডে যোগ হয়েছে। শেষ হলে খুলে ইনস্টল করুন।',
  // --- download popup / folder picker
  'Download file': 'ফাইল ডাউনলোড',
  'Rename': 'নাম বদলান',
  'File name': 'ফাইলের নাম',
  'Size': 'সাইজ',
  'Type': 'ধরন',
  'Source': 'সোর্স',
  'Download mode': 'ডাউনলোড মোড',
  'Link': 'লিংক',
  'Save to': 'সেভ হবে',
  'Change': 'বদলান',
  'Choose folder': 'ফোল্ডার বাছুন',
  'Select this folder': 'এই ফোল্ডার নিন',
  'New folder': 'নতুন ফোল্ডার',
  'Folder name': 'ফোল্ডারের নাম',
  'Create': 'তৈরি করুন',
  'No folders here': 'এখানে কোনো ফোল্ডার নেই',
  'Internal storage': 'ইন্টারনাল স্টোরেজ',
  'SDM folder': 'SDM ফোল্ডার',
  'Movies': 'মুভিজ',
  'Music': 'মিউজিক',
  'Documents': 'ডকুমেন্টস',
  'Fast multi-part · resumable': 'দ্রুত মাল্টি-পার্ট · রিজিউম করা যায়',
  'Enter a file name': 'ফাইলের নাম লিখুন',
  'Enter a valid http/https link': 'সঠিক http/https লিংক দিন',
  'Cannot save to this folder. Please choose another one.':
      'এই ফোল্ডারে সেভ করা যাচ্ছে না। অন্য ফোল্ডার বাছুন।',
  'Storage permission is needed to browse folders.':
      'ফোল্ডার দেখার জন্য স্টোরেজ অনুমতি দরকার।',
  'Allow access': 'অনুমতি দিন',
  'Downloads on': 'ডাউনলোড চালু',
  'Downloads off': 'ডাউনলোড বন্ধ',
  'Pause all': 'সব পজ',
  'Resume all': 'সব রিজিউম',
  'Download complete': 'ডাউনলোড সম্পূর্ণ',
  'Download failed': 'ডাউনলোড ব্যর্থ',
  'New update': 'নতুন আপডেট',
  'Developer': 'ডেভেলপার',
  // --- notification settings, selection
  'Notification settings': 'নোটিফিকেশন সেটিংস',
  'Reset to default': 'ডিফল্টে ফিরুন',
  'Notification settings reset': 'নোটিফিকেশন সেটিংস রিসেট হয়েছে',
  'Notifications are blocked': 'নোটিফিকেশন বন্ধ করা আছে',
  'Allow them to see download progress and finished alerts.': 'ডাউনলোডের অগ্রগতি ও শেষ হওয়ার খবর দেখতে অনুমতি দিন।',
  'Allow': 'অনুমতি দিন',
  'Notifications are allowed': 'নোটিফিকেশনের অনুমতি দেওয়া আছে',
  'While downloading': 'ডাউনলোড চলার সময়',
  'Show progress details': 'অগ্রগতির বিবরণ দেখান',
  'Percent and size in the notification': 'নোটিফিকেশনে শতাংশ ও সাইজ',
  'Separate notification for each download': 'প্রতিটি ডাউনলোডের আলাদা নোটিফিকেশন',
  'Off: one combined notification': 'বন্ধ থাকলে একটাই সম্মিলিত নোটিফিকেশন',
  'Show speed': 'স্পিড দেখান',
  'Current download speed': 'বর্তমান ডাউনলোড স্পিড',
  'Show time left': 'বাকি সময় দেখান',
  'Estimated time remaining': 'আনুমানিক বাকি সময়',
  'Pause / Resume buttons': 'পজ / রিজিউম বোতাম',
  'Control downloads from the notification': 'নোটিফিকেশন থেকেই ডাউনলোড নিয়ন্ত্রণ',
  'When a download ends': 'ডাউনলোড শেষ হলে',
  'Notify when a file is saved': 'ফাইল সেভ হলে জানান',
  'Notify when a download fails': 'ডাউনলোড ব্যর্থ হলে জানান',
  'Sound': 'শব্দ',
  'Play a sound': 'শব্দ বাজান',
  'Vibrate': 'ভাইব্রেট',
  'Vibrate the phone': 'ফোন কাঁপান',
  'Pop-up on screen': 'স্ক্রিনে পপ-আপ',
  'Show a banner at the top of the screen': 'স্ক্রিনের ওপরে ব্যানার দেখান',
  'Privacy': 'গোপনীয়তা',
  'Show on lock screen': 'লক স্ক্রিনে দেখান',
  'Off: hides the file names while the phone is locked': 'বন্ধ থাকলে ফোন লক থাকা অবস্থায় ফাইলের নাম লুকানো থাকবে',
  'Send test notification': 'টেস্ট নোটিফিকেশন পাঠান',
  'See how a finished download alert looks': 'ডাউনলোড শেষের নোটিফিকেশন দেখতে কেমন দেখুন',
  'Test notification sent': 'টেস্ট নোটিফিকেশন পাঠানো হয়েছে',
  'This is a test notification': 'এটি একটি টেস্ট নোটিফিকেশন',
  'System notification settings': 'সিস্টেম নোটিফিকেশন সেটিংস',
  'Channels, importance and more in Android': 'অ্যান্ড্রয়েডের চ্যানেল, গুরুত্ব ইত্যাদি',
  'Downloading': 'ডাউনলোড হচ্ছে',
  'left': 'বাকি',
  'Could not create the folder': 'ফোল্ডার তৈরি করা যায়নি',
  'No subfolders': 'কোনো সাবফোল্ডার নেই',
  'Use this folder': 'এই ফোল্ডার ব্যবহার করুন',
  'Cannot open this folder': 'ফোল্ডারটি খোলা যাচ্ছে না',
  'Speed mode': 'স্পিড মোড',
  'Fast: 4 parts at once, can resume': 'দ্রুত: ৪ ভাগে একসাথে, রিজিউম করা যায়',
  'Single stream, cannot resume': 'সিঙ্গেল স্ট্রিম, রিজিউম করা যায় না',
  'Use this folder for future downloads': 'পরের ডাউনলোডেও এই ফোল্ডার ব্যবহার করুন',
  'Allow "All files access" to choose a folder. Files are saved in the app folder for now.': 'ফোল্ডার বাছতে "সব ফাইল অ্যাক্সেস" অনুমতি দিন। আপাতত ফাইল অ্যাপের নিজস্ব ফোল্ডারে সেভ হবে।',
  'Select all': 'সব বাছুন',
  'Delete': 'মুছুন',
  'Also delete the files from the phone': 'ফোন থেকে ফাইলগুলোও মুছুন',
  // --- media capture
  'Video': 'ভিডিও',
  'Audio': 'অডিও',
  'Download best quality': 'সেরা কোয়ালিটিতে ডাউনলোড',
  'Best': 'সেরা',
  'No audio found yet. Play it on the page and it appears here.': 'এখনো কোনো অডিও পাওয়া যায়নি। পেজে চালালে এখানে আসবে।',
  'No video found yet. Play it on the page and it appears here.': 'এখনো কোনো ভিডিও পাওয়া যায়নি। পেজে চালালে এখানে আসবে।',
  'Protected (DRM) videos and live streams cannot be downloaded.': 'সুরক্ষিত (DRM) ভিডিও ও লাইভ স্ট্রিম ডাউনলোড করা যায় না।',
  'Protected stream, cannot be downloaded': 'সুরক্ষিত স্ট্রিম, ডাউনলোড করা যায় না',
  'Live stream, cannot be downloaded': 'লাইভ স্ট্রিম, ডাউনলোড করা যায় না',
  'Sound is a separate stream: also download it from the Audio tab': 'সাউন্ড আলাদা স্ট্রিমে আছে: অডিও ট্যাব থেকে সেটাও নামান',
  'Video stream · saved in pieces, resumable': 'ভিডিও স্ট্রিম · টুকরো টুকরো করে সেভ, রিজিউম করা যায়',
  'Protected (encrypted) streams cannot be downloaded': 'সুরক্ষিত (এনক্রিপ্টেড) স্ট্রিম ডাউনলোড করা যায় না',
  'Live streams cannot be downloaded': 'লাইভ স্ট্রিম ডাউনলোড করা যায় না',
  'No video found in this stream': 'এই স্ট্রিমে কোনো ভিডিও পাওয়া যায়নি',
  'Tap to download': 'ডাউনলোডে ট্যাপ করুন',
  'Downloading update': 'আপডেট নামছে',
  'Install update': 'আপডেট ইনস্টল করুন',
  'Update now': 'এখনই আপডেট করুন',
  'Update available': 'নতুন আপডেট এসেছে',
  'Download and install the new version now?': 'নতুন ভার্সন এখন ডাউনলোড করে ইনস্টল করবেন?',
  'Later': 'পরে',
  'only the changed part': 'শুধু বদলানো অংশ',
  'Downloading update (changed part only)': 'আপডেট নামছে (শুধু বদলানো অংশ)',
  'Applying update…': 'আপডেট বসানো হচ্ছে…',
  'Folders': 'ফোল্ডার',
  'Sort files into folders by type': 'ফাইলের ধরন অনুযায়ী আলাদা ফোল্ডারে রাখুন',
  'Video, Music, Images, Apps, Archives and Documents each go to their own folder inside the download folder. A folder you pick by hand is always used as it is.': 'ভিডিও, মিউজিক, ছবি, অ্যাপ, আর্কাইভ ও ডকুমেন্ট ডাউনলোড ফোল্ডারের ভেতরে নিজ নিজ ফোল্ডারে যাবে। আপনি নিজে ফোল্ডার বাছলে সেটাই ব্যবহার হবে।',
  'Auto by file type': 'অটো (ধরন অনুযায়ী)',
  'Update ready': 'আপডেট তৈরি',
  'The new version is downloaded. Install it now?': 'নতুন ভার্সন নামানো হয়ে গেছে। এখন ইনস্টল করবেন?',
  'Install now': 'এখনই ইনস্টল',
  'Downloaded in the background · ready to install': 'ব্যাকগ্রাউন্ডে নামানো হয়েছে · ইনস্টলের জন্য তৈরি',
  'Downloaded · ready to install': 'নামানো হয়েছে · ইনস্টলের জন্য তৈরি',
  'Auto-update': 'অটো-আপডেট',
  'Download new versions by itself on Wi-Fi. You only tap Install.': 'নতুন ভার্সন Wi-Fi তে নিজে নিজে নামবে। আপনাকে শুধু Install চাপতে হবে।',
  'SDM is updated': 'SDM আপডেট হয়েছে',
  "What's new": 'নতুন কী যোগ হলো',
  'Improvements and bug fixes.': 'উন্নতি ও বাগ ফিক্স।',
  'Got it': 'বুঝেছি',
  'Update failed': 'আপডেট ব্যর্থ',
  'Update download failed. Check your internet and try again.': 'আপডেট ডাউনলোড হয়নি। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
  'Update download incomplete': 'আপডেট ডাউনলোড অসম্পূর্ণ',
  'Could not open the installer. Allow "Install unknown apps" for SDM.': 'ইনস্টলার খোলা যায়নি। SDM-কে "অজানা অ্যাপ ইনস্টল" অনুমতি দিন।',
  'Could not open the installer.': 'ইনস্টলার খোলা যায়নি।',
  'Download speed & queue': 'ডাউনলোড স্পিড ও কিউ',
  'Auto resume, queue, speed limit': 'অটো রিজিউম, কিউ, স্পিড লিমিট',
  'Connection': 'কানেকশন',
  'Resume automatically': 'নিজে থেকে আবার চালু',
  'When the internet is lost or a download fails because of the network, SDM waits and continues by itself when the internet is back': 'ইন্টারনেট চলে গেলে বা নেটওয়ার্কের কারণে ডাউনলোড ব্যর্থ হলে SDM অপেক্ষা করে এবং নেট ফিরলে নিজে থেকেই আবার চালু করে',
  'Queue': 'কিউ',
  'Downloads at the same time': 'একসাথে ডাউনলোড',
  'The others wait in the queue and start by themselves': 'বাকিগুলো কিউতে অপেক্ষা করে এবং নিজে থেকে শুরু হয়',
  'Speed limit': 'স্পিড লিমিট',
  'Speed limit for downloads': 'ডাউনলোডের স্পিড লিমিট',
  'Unlimited': 'সীমাহীন',
  'Off': 'বন্ধ',
  'shared equally between running downloads': 'চলমান ডাউনলোডগুলোর মধ্যে সমান ভাগ হয়',
  'Limit while the browser is open': 'ব্রাউজার খোলা থাকলে লিমিট',
  'keeps internet free for browsing and watching videos': 'ব্রাউজ ও ভিডিও দেখার জন্য নেট খালি রাখে',
  'Custom (KB/s)': 'নিজের মান (KB/s)',
  'Set': 'সেট',
  'Browser is open: the lower limit applies now': 'ব্রাউজার খোলা: এখন কম লিমিট চলছে',
  'Queued': 'কিউতে আছে',
  'Waiting for internet': 'ইন্টারনেটের অপেক্ষায়',
  'This build was signed with a different key, so Android will not install it over the current app. Uninstall SDM once and install the new version; after that updates install normally.': 'এই বিল্ড আলাদা সাইনিং কি দিয়ে বানানো, তাই অ্যান্ড্রয়েড বর্তমান অ্যাপের ওপর ইনস্টল করবে না। একবার SDM আনইনস্টল করে নতুন ভার্সন ইনস্টল করুন; এরপর থেকে আপডেট স্বাভাবিকভাবে ইনস্টল হবে।',
  'The downloaded update file is damaged. Try again.': 'ডাউনলোড করা আপডেট ফাইলটি নষ্ট। আবার চেষ্টা করুন।',
};
