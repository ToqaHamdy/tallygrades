/* Tally Grades in Arabic.
   index.html loads this file only when Arabic is chosen (the ع button at the top, or Settings > Appearance).
   The app writes its pages in English; this file swaps every piece of English text for its Arabic line as it appears,
   so the pages, the buttons, the messages and the hints all show in Arabic, right to left.
   T holds the lines: a line with {} has a number or a name in that place ({1}, {2} pick them in another order),
   and a line can be a function when the Arabic word changes with the number (1 طالب, 2 طالبين, 3 طلاب, 11 طالبًا).
   Names of students, TAs, courses and groups are never in T, so they stay as they are written. */
(function () {
  'use strict';
  var de = document.documentElement;
  if (de.lang !== 'ar') return;

  /* Arabic counted nouns: pl(5, N.st) gives "5 طلاب" */
  function num(x) { var m = String(x).match(/^\s*(\d+)\s*$/); return m ? Number(m[1]) : null; }
  function pl(x, w) {
    var n = num(x); if (n == null) return x + ' ' + w[2];
    if (n === 0) return '0 ' + w[3];
    if (n === 1) return w[0];
    if (n === 2) return w[1];
    var r = n % 100; return n + ' ' + (r >= 3 && r <= 10 ? w[2] : w[3]);
  }
  /* "3 weeks in a row": the Arabic adjective follows the number too */
  function inRow(x) {
    var n = num(x); if (n == null) return x + ' أسابيع متتالية';
    return n === 1 ? 'أسبوع واحد' : n === 2 ? 'أسبوعين متتاليين' : n % 100 >= 3 && n % 100 <= 10 ? n + ' أسابيع متتالية' : n + ' أسبوعًا متتاليًا';
  }
  var N = {
    st: ['طالب واحد', 'طالبين', 'طلاب', 'طالبًا'],
    wk: ['أسبوع واحد', 'أسبوعين', 'أسابيع', 'أسبوعًا'],
    gr: ['مجموعة واحدة', 'مجموعتين', 'مجموعات', 'مجموعة'],
    mk: ['درجة واحدة', 'درجتين', 'درجات', 'درجة'],
    ta: ['معيد واحد', 'معيدين', 'معيدين', 'معيدًا'],
    ph: ['صورة واحدة', 'صورتين', 'صور', 'صورة'],
    tm: ['فريق واحد', 'فريقين', 'فرق', 'فريقًا'],
    it: ['بند واحد', 'بندين', 'بنود', 'بندًا'],
    nm: ['اسم واحد', 'اسمين', 'أسماء', 'اسمًا'],
    cl: ['خلية واحدة', 'خليتين', 'خلايا', 'خلية'],
    ln: ['سطر واحد', 'سطرين', 'أسطر', 'سطرًا'],
    sh: ['ورقة واحدة', 'ورقتين', 'أوراق', 'ورقة'],
    ch: ['تغيير واحد', 'تغييرين', 'تغييرات', 'تغييرًا'],
    co: ['عمود واحد', 'عمودين', 'أعمدة', 'عمودًا'],
    rq: ['طلب واحد', 'طلبين', 'طلبات', 'طلبًا'],
    mi: ['دقيقة واحدة', 'دقيقتين', 'دقائق', 'دقيقة']
  };

  var T = {
    /* top bar, menus, theme */
    'Dark mode': 'الوضع الداكن', 'Light mode': 'الوضع الفاتح', 'Main': 'القائمة الرئيسية', 'Menu': 'القائمة',
    'Search a student (name or ID) or a TA': 'ابحث عن طالب (بالاسم أو الرقم) أو معيد',
    'Search a student or a TA (Ctrl K)': 'ابحث عن طالب أو معيد (Ctrl K)', 'Search a student or a TA': 'ابحث عن طالب أو معيد',
    'Open it': 'افتحه', 'Something went wrong ({}).': 'حدث خطأ ({}).', 'Please log in again.': 'من فضلك سجّل الدخول مرة أخرى.',
    'Could not reach the server. Check your internet.': 'تعذّر الوصول إلى الخادم. تأكد من اتصال الإنترنت.',
    'Entered by {}, {}': 'أدخلها {1}، {2}', 'Entered by {}': 'أدخلها {}', 'extra, up to': 'إضافية، حتى', 'extra, up to {}': 'إضافية، حتى {}',
    'out of': 'من', 'out of {}': 'من {}', 'done = {}': 'تم = {}',
    'Tick or untick everyone shown': 'علّم أو ألغِ تعليم كل الظاهرين', 'One step left': 'خطوة واحدة متبقية',
    'Today': 'اليوم', 'Yesterday': 'أمس', 'Open {}': 'فتح {}',
    'Sun': 'الأحد', 'Mon': 'الإثنين', 'Tue': 'الثلاثاء', 'Wed': 'الأربعاء', 'Thu': 'الخميس', 'Fri': 'الجمعة', 'Sat': 'السبت',
    'Sunday': 'الأحد', 'Monday': 'الإثنين', 'Tuesday': 'الثلاثاء', 'Wednesday': 'الأربعاء', 'Thursday': 'الخميس', 'Friday': 'الجمعة', 'Saturday': 'السبت',
    'Show password': 'إظهار كلمة المرور', 'Hide password': 'إخفاء كلمة المرور',

    /* student page */
    'You missed': 'فاتك', '{} section weeks in a row': function (n) { return inRow(n) + ' من السكشن'; },
    'more week': 'أسبوع إضافي', 'more weeks': 'أسابيع إضافية',
    '{} more week': function () { return 'أسبوع إضافي واحد'; },
    '{} more weeks': function (n) { return pl(n, ['أسبوع إضافي واحد', 'أسبوعين إضافيين', 'أسابيع إضافية', 'أسبوعًا إضافيًا']); },
    'You can miss': 'يمكنك أن تغيب', 'and stay at 75% or above.': 'وتظل نسبتك 75% أو أكثر.',
    'Do not miss any more weeks. One more absence takes you below 75%.': 'لا تغب أي أسبوع آخر. غياب واحد إضافي ينزل بك تحت 75%.',
    'You are below 75%. Talk to your TA.': 'نسبة حضورك أقل من 75%. تحدّث مع معيدك.',
    'You': 'أنت', 'Group': 'المجموعة', 'Attendance': 'الحضور', 'Total marks': 'مجموع الدرجات',
    'Group: the average of the {} students in group {}.': function (n, g) { return 'المجموعة: متوسط ' + pl(n, N.st) + ' في مجموعة ' + g + '.'; },
    'from your attendance %': 'من نسبة حضورك', 'done ✓': 'تم ✓', 'not done yet': 'لم يتم بعد', 'My marks': 'درجاتي',
    'A dash means no mark yet.': 'الشرطة تعني أنه لا توجد درجة بعد.', 'Loading your attendance': 'جارٍ تحميل حضورك',
    'Your attendance shows here after your first check-in from this phone.': 'سيظهر حضورك هنا بعد أول تسجيل حضور من هذا الهاتف.',
    'Present': 'حاضر', 'Absent': 'غائب', 'Excused': 'بعذر', 'present': 'حاضر', 'absent': 'غائب', 'excused': 'بعذر',
    'Team leader: {}': 'قائد الفريق: {}', 'No check-in': 'لم يسجّل', 'Mid': 'ميد', 'Final': 'النهائي',
    'Week {}: {}': 'الأسبوع {1}: {2}', 'Room {}': 'قاعة {}', 'My section': 'سكشني', 'My history': 'سجلي', 'Group {}': 'مجموعة {}',
    'My attendance': 'حضوري', 'P present, E excused, empty: no check-in that week. Open this page any time to see it again.': 'P حاضر، E بعذر، فارغ: لم يسجّل حضورًا في هذا الأسبوع. افتح هذه الصفحة في أي وقت لتراها مرة أخرى.',
    'Back': 'رجوع', 'Registered': 'مسجّل', 'In the section, scan the QR code on the TA\'s screen and press': 'في السكشن، امسح رمز QR الظاهر على شاشة المعيد واضغط',
    'Your ID is already filled in on this phone.': 'رقمك مكتوب بالفعل على هذا الهاتف.',
    'Check in': 'سجّل حضورك', 'One time only': 'مرة واحدة فقط', 'Register your phone': 'سجّل هاتفك',
    'Do this once. In every section after that, you scan the QR code and press Check in.': 'تفعل ذلك مرة واحدة فقط. في كل سكشن بعدها تمسح رمز QR وتضغط «سجّل حضورك».',
    'Your student ID': 'رقمك الجامعي', 'Register': 'تسجيل', 'Use your own phone. Each phone can be registered to one student only.': 'استخدم هاتفك الشخصي. كل هاتف يُسجَّل لطالب واحد فقط.',
    'Type your ID': 'اكتب رقمك', 'Registering': 'جارٍ التسجيل', 'Could not reach the server': 'تعذّر الوصول إلى الخادم',
    'Check your internet and try again.': 'تأكد من اتصال الإنترنت وحاول مرة أخرى.', 'Try again': 'حاول مرة أخرى', 'Loading': 'جارٍ التحميل',
    'No connection': 'لا يوجد اتصال', 'Check your internet, then tap Try again.': 'تأكد من اتصال الإنترنت، ثم اضغط «حاول مرة أخرى».',
    'Check-in is closed': 'تسجيل الحضور مغلق', 'Ask your TA to open it, then scan the QR code again.': 'اطلب من المعيد أن يفتحه، ثم امسح رمز QR مرة أخرى.',
    'This phone is registered to you.': 'هذا الهاتف مسجّل باسمك.', 'Not you?': 'لست أنت؟', 'Checking in as': 'تسجيل الحضور باسم',
    'Check in to today\'s section{}.': 'سجّل حضورك في سكشن اليوم{}.', 'Check in to today\'s section': 'سجّل حضورك في سكشن اليوم',
    'Code on the TA\'s screen': 'الرمز الظاهر على شاشة المعيد',
    'Each phone can check in one student. Checking in for someone else is recorded.': 'كل هاتف يسجّل حضور طالب واحد فقط. تسجيل الحضور لشخص آخر يُسجَّل ويُراجَع.',
    'Type the code': 'اكتب الرمز', 'Write the 4 digits shown on the TA\'s screen.': 'اكتب الأرقام الأربعة الظاهرة على شاشة المعيد.',
    'Checking in': 'جارٍ تسجيل الحضور', 'Check your internet and press Check in again.': 'تأكد من اتصال الإنترنت واضغط «سجّل حضورك» مرة أخرى.',
    'Check-in is open': 'تسجيل الحضور مفتوح', 'Remove from the bar': 'إزالة من الشريط', 'Open groups': 'المجموعات المفتوحة',
    'Team {}': 'فريق {}', 'Team not found.': 'لم يتم العثور على الفريق.', 'This group is not one of yours.': 'هذه المجموعة ليست من مجموعاتك.',
    'Could not connect. Refresh the page.': 'تعذّر الاتصال. أعد تحميل الصفحة.',

    /* landing */
    'QR check-in': 'الحضور برمز QR', 'One scan per student, one phone per student.': 'مسحة واحدة لكل طالب، وهاتف واحد لكل طالب.',
    'Live attendance': 'الحضور لحظة بلحظة', 'See who is in, group by group, as it happens.': 'شاهد من حضر، مجموعة بمجموعة، في نفس اللحظة.',
    'Groups and teams': 'المجموعات والفرق', 'Grade a whole project team in one row.': 'قيّم فريق مشروع كاملًا في سطر واحد.',
    'Excel in and out': 'إكسل استيرادًا وتصديرًا', 'Import attendance, export the final sheet.': 'استورد الحضور، وصدّر الشيت النهائي.',
    'Lab attendance and grades': 'حضور ودرجات السكاشن', 'Every section,': 'كل سكشن،', 'counted.': 'محسوب.',
    'Students check in with a QR code. TAs follow every group live, grade quizzes and project teams, and download the course sheet in one click.': 'الطلاب يسجّلون حضورهم برمز QR. والمعيدون يتابعون كل مجموعة لحظة بلحظة، ويرصدون درجات الكويزات وفرق المشاريع، وينزّلون شيت المادة بضغطة واحدة.',
    'Sign in': 'تسجيل الدخول', 'For TAs and the admin.': 'للمعيدين والمسؤول.', 'New TA?': 'معيد جديد؟', 'Create an account': 'إنشاء حساب',
    'I am a student': 'أنا طالب', 'Register your phone and see your attendance': 'سجّل هاتفك وتابع حضورك', 'Signing in': 'جارٍ تسجيل الدخول',

    /* staff navigation */
    'Admin': 'مسؤول', 'Dashboard': 'لوحة المتابعة', 'My schedule': 'جدولي', 'Take attendance': 'أخذ الحضور', 'Enter marks': 'رصد الدرجات',
    'Ask the assistant': 'اسأل المساعد', 'Courses': 'المواد', 'Attendance from a photo': 'الحضور من صورة', 'Import attendance': 'استيراد الحضور',
    'Download final sheet': 'تنزيل الشيت النهائي', 'Registration QR': 'رمز QR للتسجيل', 'Term start': 'بداية الترم', 'Download backup': 'تنزيل نسخة احتياطية',
    'Settings': 'الإعدادات', 'Tools': 'الأدوات', 'More': 'المزيد', 'Type quiz, assignment and exam marks': 'اكتب درجات الكويزات والتكليفات والامتحانات',
    'Open a check-in with a QR code': 'افتح تسجيل حضور برمز QR', 'Escape': 'Esc', 'Log in': 'تسجيل الدخول', 'TA': 'معيد', 'Manage TAs': 'إدارة المعيدين',
    'Account': 'الحساب', 'your sections this week': 'سكاشنك هذا الأسبوع', 'Log out': 'تسجيل الخروج',

    /* settings */
    'This file is not an image. Choose a JPG or PNG photo.': 'هذا الملف ليس صورة. اختر صورة JPG أو PNG.',
    'You log in with your name now. Choose a username and you log in with it from now on.': 'أنت تسجّل الدخول باسمك الآن. اختر اسم مستخدم لتسجّل الدخول به من الآن فصاعدًا.',
    'Paste the key': 'الصق المفتاح', 'Paper sheets with Gemini': 'الكشوف الورقية مع Gemini',
    'A free Gemini key lets every TA turn a photo of a paper attendance sheet into attendance. Make one at': 'مفتاح Gemini المجاني يتيح لكل معيد تحويل صورة كشف الحضور الورقي إلى حضور مسجّل. أنشئ مفتاحًا من',
    '(Create API key), then paste it here. It is kept in the database, never in the page, and only TAs who are logged in can use it.': '(Create API key)، ثم الصقه هنا. يُحفظ في قاعدة البيانات وليس في الصفحة، ولا يستخدمه إلا المعيدون المسجّلون الدخول.',
    'Gemini API key': 'مفتاح Gemini API', 'Save the key': 'حفظ المفتاح', 'Remove the key': 'حذف المفتاح', 'Choose a username': 'اختر اسم مستخدم',
    'Home': 'الرئيسية', 'Your profile and password, and how the site looks on this device.': 'ملفك الشخصي وكلمة المرور، وشكل الموقع على هذا الجهاز.',
    'Profile': 'الملف الشخصي', 'Upload a photo': 'رفع صورة', 'Remove photo': 'حذف الصورة',
    'A photo of your face works best. It is cropped to a square and made small before it is saved.': 'الأفضل صورة لوجهك. تُقص على شكل مربع وتُصغَّر قبل حفظها.',
    'Username and password': 'اسم المستخدم وكلمة المرور', 'Username': 'اسم المستخدم', 'Current password': 'كلمة المرور الحالية',
    'New password': 'كلمة المرور الجديدة', 'New password again': 'كلمة المرور الجديدة مرة أخرى', 'Save': 'حفظ',
    'Username: 3 to 30 letters, numbers, dots or dashes. Password: at least 6 characters. Other devices logged in as you are logged out.': 'اسم المستخدم: من 3 إلى 30 حرفًا أو رقمًا أو نقطة أو شرطة. كلمة المرور: 6 أحرف على الأقل. الأجهزة الأخرى المسجّلة باسمك سيتم تسجيل خروجها.',
    'Appearance': 'المظهر', 'Dark': 'داكن', 'Light': 'فاتح', 'Saved on this device only.': 'يُحفظ على هذا الجهاز فقط.',
    'Language': 'اللغة', 'The whole site, on this device.': 'الموقع كله، على هذا الجهاز.',
    'A key is saved ({}).': 'يوجد مفتاح محفوظ ({}).', 'No key yet.': 'لا يوجد مفتاح بعد.', 'Paste the key first.': 'الصق المفتاح أولًا.',
    'Checking the key with Google...': 'جارٍ التحقق من المفتاح مع Google...',
    'Google did not accept this key{} Copy it again from aistudio.google.com/api-keys.': 'Google لم يقبل هذا المفتاح{} انسخه مرة أخرى من aistudio.google.com/api-keys.',
    'Saved. Every TA can now use Attendance from a photo.': 'تم الحفظ. يمكن لكل معيد الآن استخدام «الحضور من صورة».',
    'Could not reach Google to check the key. Check your internet.': 'تعذّر الوصول إلى Google للتحقق من المفتاح. تأكد من اتصال الإنترنت.',
    'Remove the Gemini key? Attendance from a photo stops working until a new key is saved.': 'حذف مفتاح Gemini؟ ستتوقف خاصية «الحضور من صورة» حتى يُحفظ مفتاح جديد.',
    'Removed.': 'تم الحذف.', 'Photo saved.': 'تم حفظ الصورة.', 'Enter': 'Enter', 'Remove your photo?': 'حذف صورتك؟', 'Photo removed.': 'تم حذف الصورة.',
    'The two new passwords are not the same.': 'كلمتا المرور الجديدتان غير متطابقتين.',
    'Saved. Log in next time with the username {}.': 'تم الحفظ. سجّل الدخول في المرة القادمة باسم المستخدم {}.',
    'Password': 'كلمة المرور',

    /* first setup and TA sign up */
    'First time': 'أول مرة', 'Set up Tally Grades': 'إعداد Tally Grades',
    'You become the admin. TAs can then create their accounts, and you confirm them.': 'ستصبح المسؤول. بعدها يُنشئ المعيدون حساباتهم، وتؤكدها أنت.',
    'Your name': 'اسمك', 'Username: 3 to 30 letters or numbers, no spaces. Password: at least 6 characters.': 'اسم المستخدم: من 3 إلى 30 حرفًا أو رقمًا بدون مسافات. كلمة المرور: 6 أحرف على الأقل.',
    'Create admin': 'إنشاء حساب المسؤول', 'This is a TA account. Go back and choose "I am a TA".': 'هذا حساب معيد. ارجع واختر «أنا معيد».',
    'Your courses': 'موادك', 'New TA': 'معيد جديد', 'The admin confirms your account, then you can log in.': 'يؤكد المسؤول حسابك، وبعدها يمكنك تسجيل الدخول.',
    'Full name': 'الاسم بالكامل', 'Password again': 'كلمة المرور مرة أخرى', 'Send request': 'إرسال الطلب', 'The two passwords are not the same.': 'كلمتا المرور غير متطابقتين.',
    'Request sent': 'تم إرسال الطلب', 'The admin will confirm your account. After that, log in with your username': 'سيؤكد المسؤول حسابك. بعد ذلك سجّل الدخول باسم المستخدم',
    'Go to log in': 'الذهاب لتسجيل الدخول',

    /* home and schedule */
    'No sections for {} in the schedule yet.': 'لا توجد سكاشن لـ {} في الجدول بعد.', 'Live': 'مباشر', 'Done': 'انتهى', 'Now': 'الآن', 'Next': 'التالي',
    '· today': '· اليوم', 'No sections today.': 'لا توجد سكاشن اليوم.', '· now:': '· الآن:', '· next:': '· التالي:', '· no more sections today': '· لا مزيد من السكاشن اليوم',
    'now:': 'الآن:', 'next:': 'التالي:', 'no more sections today': 'لا مزيد من السكاشن اليوم', 'today': 'اليوم',
    'Attendance {}%': 'الحضور {}%', 'Missed {} weeks in a row': function (n) { return 'غاب ' + inRow(n); },
    '{} not done: {}': '{1} لم يتم: {2}', 'your groups': 'مجموعاتك', 'all groups': 'كل المجموعات', 'group {}': 'مجموعة {}', 'groups {}': 'المجموعات {}',
    'Show fewer': 'عرض أقل', 'Show all {}': 'عرض الكل ({})', 'Show all': 'عرض الكل',
    'Everyone is on track: nobody under 75%, nobody missing two weeks in a row.': 'الكل على المسار الصحيح: لا أحد تحت 75%، ولا أحد غاب أسبوعين متتاليين.',
    'Needs follow-up': 'يحتاج متابعة', 'my groups': 'مجموعاتي', 'phones registered': 'هواتف مسجّلة', 'check-ins live now': 'تسجيلات حضور مفتوحة الآن',
    'Your sections are not in the schedule yet.': 'سكاشنك ليست في الجدول بعد.', 'My whole week →': 'أسبوعي كاملًا ←', 'My sections': 'سكاشني', 'Sections': 'السكاشن',
    'Not in the schedule': 'ليست في الجدول',
    'From the schedule. Press a section to open its group. Today\'s sections say Done, Now, Live (check-in open) or Next.': 'من الجدول. اضغط على سكشن لفتح مجموعته. سكاشن اليوم مكتوب عليها: انتهى، الآن، مباشر (الحضور مفتوح) أو التالي.',
    'Mark': 'رصد', 'Other': 'أخرى', 'Search a student, an ID, a course or a group': 'ابحث عن طالب أو رقم أو مادة أو مجموعة',
    'All ({})': 'الكل ({})', 'Marks ({})': 'الدرجات ({})', 'Attendance ({})': 'الحضور ({})', 'Groups and setup ({})': 'المجموعات والإعداد ({})',
    'Nothing matches.': 'لا توجد نتائج مطابقة.', 'Nothing written yet.': 'لم يُكتب شيء بعد.', 'Show more ({} left)': 'عرض المزيد (متبقٍ {})',
    'Search a TA or a course': 'ابحث عن معيد أو مادة', '{} groups': function (n) { return pl(n, N.gr); },
    'No TA or course matches “{}”.': 'لا يوجد معيد أو مادة تطابق «{}».', 'My groups ({})': 'مجموعاتي ({})', 'All groups ({})': 'كل المجموعات ({})', 'Courses ({})': 'المواد ({})',
    'The grade distribution of each course. It is the same for every group of the course. The attendance mark is calculated from each student\'s attendance %.': 'توزيع درجات كل مادة. وهو نفسه لكل مجموعات المادة. وتُحسب درجة الحضور من نسبة حضور كل طالب.',
    'No courses yet. Upload a course Excel sheet first, then set its grades here.': 'لا توجد مواد بعد. ارفع شيت إكسل للمادة أولًا، ثم حدّد درجاتها هنا.',
    'All courses': 'كل المواد', 'New request': 'طلب جديد', 'Confirm →': 'تأكيد ←', 'Reject': 'رفض', 'Waiting for you to confirm': 'في انتظار تأكيدك',
    'Set username': 'تعيين اسم المستخدم', 'Remove': 'إزالة', '+ Add a TA': '+ إضافة معيد', 'Show check-in': 'عرض تسجيل الحضور', 'Open': 'فتح',
    'Open in a new browser tab': 'فتح في تبويب جديد', 'Open group {} in a new tab': 'فتح مجموعة {} في تبويب جديد', 'Grades →': 'الدرجات ←', 'Change TA': 'تغيير المعيد',
    'Delete': 'حذف', 'This is my group': 'هذه مجموعتي', 'No TA yet': 'لا يوجد معيد بعد',
    'This group has no TA account in the site yet. The name is from the schedule.': 'هذه المجموعة ليس لها حساب معيد على الموقع بعد. الاسم مأخوذ من الجدول.',
    'Live now': 'مباشر الآن', 'Belongs to {}': 'تابعة لـ {}', '{}% of phones registered': '{}% من الهواتف مسجّلة', 'not set': 'غير محدد', 'Leader:': 'القائد:',
    'Grade team →': 'تقييم الفريق ←', 'Search a group, TA or team': 'ابحث عن مجموعة أو معيد أو فريق', 'Search a group or TA': 'ابحث عن مجموعة أو معيد',
    'No groups yet. Upload the course Excel sheet, or paste one group.': 'لا توجد مجموعات بعد. ارفع شيت إكسل للمادة، أو الصق مجموعة واحدة.',
    'Groups': 'المجموعات', 'Project teams ({})': 'فرق المشاريع ({})',
    '{} project teams, {} students': function (t, s) { return pl(t, ['فريق مشروع واحد', 'فريقا مشروع', 'فرق مشاريع', 'فريق مشروع']) + '، ' + pl(s, N.st); },
    '{} students': function (n) { return pl(n, N.st); }, '{} student': function (n) { return pl(n, N.st); },
    '+ Upload an Excel sheet': '+ رفع شيت إكسل', 'Paste one group': 'لصق مجموعة واحدة', 'This week is': 'هذا الأسبوع هو',
    'You are the admin: you see every group and manage the TAs.': 'أنت المسؤول: ترى كل المجموعات وتدير المعيدين.',
    'Your course{}.': 'مادتك{}.', 'Your courses:': 'موادك:', 'Your course:': 'مادتك:',
    'Your groups are under My groups. You can open every group of your courses under All groups, and take attendance or marks there too.': 'مجموعاتك موجودة في «مجموعاتي». ويمكنك فتح كل مجموعات موادك من «كل المجموعات»، وأخذ الحضور أو رصد الدرجات منها أيضًا.',
    'group live now': 'مجموعة مباشرة الآن', 'groups live now': 'مجموعات مباشرة الآن', 'project teams': 'فرق مشاريع', 'Grades': 'الدرجات',
    'the same for every group': 'نفسها لكل المجموعات', '{} TA teach this course.': '{} معيد يدرّس هذه المادة.', '{} TAs teach this course.': function (n) { return pl(n, N.ta) + ' يدرّسون هذه المادة.'; },
    'Good morning': 'صباح الخير', 'Good afternoon': 'مساء الخير', 'Good evening': 'مساء الخير',
    'Take group {} of {} as your group?': 'تأخذ مجموعة {1} من {2} كمجموعتك؟', 'Group {} is now yours.': 'مجموعة {} أصبحت مجموعتك.',
    'Delete group {} of {} from the list? Its attendance records stay in the Log sheet.': 'حذف مجموعة {1} من {2} من القائمة؟ سجلات حضورها تبقى محفوظة.',
    'Reject the request of {}?': 'رفض طلب {}؟', 'Request rejected.': 'تم رفض الطلب.',
    'Remove {}? Their PIN stops working, and their groups become free.': 'إزالة {}؟ سيتوقف دخوله، وتصبح مجموعاته بدون معيد.',
    'from attendance %': 'من نسبة الحضور', 'extra, not in the total': 'إضافية، خارج المجموع', 'No grades set for this course yet.': 'لم تُحدَّد درجات لهذه المادة بعد.',
    '+ {} bonus': '+ {} إضافية', 'Edit grades': 'تعديل الدرجات', 'Set grades': 'تحديد الدرجات', 'Total': 'المجموع',
    'Preparing the file': 'جارٍ تجهيز الملف', 'No students to export yet.': 'لا يوجد طلاب للتصدير بعد.', 'Student Name': 'اسم الطالب', 'ID': 'الرقم',
    'Missed': 'غياب', 'Attendance %': 'نسبة الحضور', 'Course': 'المادة',
    'Downloaded: {}': 'تم التنزيل: {}', 'Downloaded:': 'تم التنزيل:', 'Preparing the backup': 'جارٍ تجهيز النسخة الاحتياطية', 'No data yet': 'لا توجد بيانات بعد',
    'Backup downloaded.': 'تم تنزيل النسخة الاحتياطية.',
    'The first day of Week 1. The site then opens every group on the current week by itself.': 'أول يوم في الأسبوع الأول. بعدها يفتح الموقع كل مجموعة على الأسبوع الحالي تلقائيًا.',
    'Week 1 starts on': 'الأسبوع الأول يبدأ في', 'Cancel': 'إلغاء', 'Saved. This week is {}.': 'تم الحفظ. هذا الأسبوع هو {}.', 'Saved.': 'تم الحفظ.',
    'For all students': 'لكل الطلاب',
    'Students scan it once, from home or anywhere, and type their ID. Their phone remembers them, so in the section they only press Check in.': 'يمسحه الطلاب مرة واحدة، من البيت أو من أي مكان، ويكتبون أرقامهم. يتذكرهم الهاتف، فلا يضغطون في السكشن إلا «سجّل حضورك».',
    'Scan to register': 'امسح للتسجيل', 'Link to share on the LMS or WhatsApp': 'رابط للمشاركة على LMS أو واتساب', 'Copy link': 'نسخ الرابط', 'Close': 'إغلاق',
    'Link copied.': 'تم نسخ الرابط.', 'Select the link and copy it.': 'حدّد الرابط وانسخه.', 'No TA (any TA can take it)': 'بدون معيد (أي معيد يمكنه أخذها)',

    /* history */
    'removed the mark': 'حذف الدرجة', 'Self': 'بنفسه', 'checked in with the QR code in {}': 'سجّل حضوره برمز QR في {}', 'removed the attendance of {}': 'حذف حضور {}',
    'The student': 'الطالب', 'Unknown': 'غير معروف', '· by the student': '· بواسطة الطالب', 'by the student': 'بواسطة الطالب',
    'Group {} · ID {}': 'مجموعة {1} · الرقم {2}', 'ID {}': 'الرقم {}',
    'Type a student name or ID, or a TA name.': 'اكتب اسم طالب أو رقمه، أو اسم معيد.', 'Student': 'طالب', 'No groups yet': 'لا توجد مجموعات بعد',
    'Nobody matches “{}”.': 'لا أحد يطابق «{}».', 'Loading the students': 'جارٍ تحميل الطلاب', 'Search a student, an ID or a TA': 'ابحث عن طالب أو رقم أو معيد',
    'History': 'السجل',
    'Everything anyone wrote: marks, attendance, groups, grade items and check-ins, with who did it and when. The newest is at the top. Press a student to see everything about them.': 'كل ما كتبه أي شخص: الدرجات والحضور والمجموعات وبنود الدرجات وتسجيلات الحضور، مع من قام بها ومتى. الأحدث في الأعلى. اضغط على طالب لترى كل ما يخصه.',
    'All': 'الكل', 'Marks': 'الدرجات', 'Groups and setup': 'المجموعات والإعداد', 'No changes yet.': 'لا توجد تغييرات بعد.',
    'Remove from the group': 'إزالة من المجموعة', 'done / not done': 'تم / لم يتم', 'Not done': 'لم يتم', 'Written by': 'كتبها', 'No mark yet': 'لا توجد درجة بعد',
    'in group {}': 'في مجموعة {}', 'TA {}': 'المعيد {}', 'team {}': 'فريق {}', 'phone registered': 'الهاتف مسجّل', 'no phone registered': 'لا يوجد هاتف مسجّل',
    'This course has no grade items yet.': 'هذه المادة ليس لها بنود درجات بعد.',
    'attendance · {} present, {} excused{}': function (p, e, x) { return 'الحضور · ' + p + ' حاضر، ' + e + ' بعذر' + x; },
    '{} present, {} excused{}': '{1} حاضر، {2} بعذر{3}', '{} present, {} excused': '{1} حاضر، {2} بعذر',
    'attendance mark': 'درجة الحضور', 'total so far': 'المجموع حتى الآن', 'marks entered': 'درجات مُدخلة', 'Attendance by week': 'الحضور حسب الأسبوع',
    'Remove from group {}': 'إزالة من مجموعة {}',
    'Remove {} ({}) from group {} of {}? Their attendance and marks stay in the history.': 'إزالة {1} ({2}) من مجموعة {3} في {4}؟ حضوره ودرجاته تبقى في السجل.',
    '{} is removed from group {}.': 'تمت إزالة {1} من مجموعة {2}.', 'This group will be yours.': 'ستكون هذه المجموعة مجموعتك.',
    'Add a group': 'إضافة مجموعة', 'Copy the Name and ID columns from Excel or the LMS and paste them here.': 'انسخ عمودي الاسم والرقم من إكسل أو LMS والصقهما هنا.',
    'Students': 'الطلاب', 'Paste a list to see how many students were found.': 'الصق قائمة لترى عدد الطلاب الذين تم العثور عليهم.', 'Save group': 'حفظ المجموعة',
    'Found {} students.': function (n) { return 'تم العثور على ' + pl(n, N.st) + '.'; },
    'No students found yet. Each line needs a name and an ID.': 'لم يتم العثور على طلاب بعد. كل سطر يحتاج اسمًا ورقمًا.',
    'Saved. {} students added.': function (n) { return 'تم الحفظ. أُضيف ' + pl(n, N.st) + '.'; },
    'Could not load the Excel reader. Check your internet and try again.': 'تعذّر تحميل قارئ ملفات إكسل. تأكد من اتصال الإنترنت وحاول مرة أخرى.',
    'Week {}': 'الأسبوع {}', 'Grade items': 'بنود الدرجات', 'Attendance (P or E)': 'الحضور (P أو E)', 'Skip': 'تخطٍّ', 'Student ID': 'رقم الطالب', 'Name': 'الاسم',
    'Import from Excel': 'استيراد من إكسل',
    'Marks and attendance from any sheet. You see every line before anything is saved, and everything is saved in your name.': 'درجات وحضور من أي شيت. ترى كل سطر قبل حفظ أي شيء، وكل شيء يُحفظ باسمك.',
    'Excel file': 'ملف إكسل', 'Check the lines': 'راجع الأسطر', 'Sheet': 'الورقة', 'Column {}': 'العمود {}',
    'What is in each column? They are guessed from the first row; change any that is wrong. Total, Notes, Group and TA are left out.': 'ماذا يوجد في كل عمود؟ تم تخمينها من الصف الأول، غيّر أي عمود خاطئ. أعمدة المجموع والملاحظات والمجموعة والمعيد يتم تجاهلها.',
    'Column in the sheet': 'العمود في الشيت', 'Example': 'مثال', 'Goes to': 'يذهب إلى', 'Choose the column with the student ID (or at least the name).': 'اختر العمود الذي فيه رقم الطالب (أو الاسم على الأقل).',
    'found by name': 'تم العثور عليه بالاسم', 'several students have this name': 'أكثر من طالب بهذا الاسم', 'not in the course': 'ليس في المادة',
    'found by name: check them': 'تم العثور عليهم بالاسم: راجعهم', 'not found': 'غير موجود', 'already the same': 'مطابق بالفعل', 'nothing new': 'لا جديد',
    'Left out: {}': 'تم تجاهل: {}', 'changes to save': 'تغييرات للحفظ', 'In the sheet': 'في الشيت', 'What changes': 'ما الذي سيتغير', 'Saving group {}': 'جارٍ حفظ مجموعة {}',
    'Could not reach Gemini. Check your internet.': 'تعذّر الوصول إلى Gemini. تأكد من اتصال الإنترنت.',
    'Gemini did not give a list. Try a clearer photo.': 'لم يُرجع Gemini قائمة. جرّب صورة أوضح.', 'Gemini answered {}': 'ردّ Gemini: {}',
    'The Gemini key is not valid. The admin can save a new one in Settings.': 'مفتاح Gemini غير صالح. يمكن للمسؤول حفظ مفتاح جديد من الإعدادات.',
    'The free Gemini limit is used up for now. Try again in a minute (or tomorrow).': 'انتهى الحد المجاني لـ Gemini حاليًا. حاول بعد دقيقة (أو غدًا).',
    'Gemini could not read the photo.': 'لم يستطع Gemini قراءة الصورة.', '{} is not a photo this browser can open.': '{} ليس صورة يستطيع هذا المتصفح فتحها.',
    'Save a free Gemini key first: Settings, then Paper sheets with Gemini.': 'احفظ مفتاح Gemini مجانيًا أولًا: الإعدادات، ثم «الكشوف الورقية مع Gemini».',
    'The admin has not saved a Gemini key yet. Ask them to add it in Settings.': 'لم يحفظ المسؤول مفتاح Gemini بعد. اطلب منه إضافته من الإعدادات.',
    'Open Settings': 'فتح الإعدادات',
    'Take a photo of the paper sheet (one or more pages). Gemini reads the names and IDs, you check every line, then it is saved as present, each student in their own group.': 'صوّر الكشف الورقي (صفحة أو أكثر). يقرأ Gemini الأسماء والأرقام، وتراجع أنت كل سطر، ثم يُحفظ الحضور، كل طالب في مجموعته.',
    'Week': 'الأسبوع', 'Photos of the sheet': 'صور الكشف', 'Read with Gemini': 'القراءة بـ Gemini', 'Save as present': 'حفظ كحضور',
    'Choose a photo of the sheet first.': 'اختر صورة الكشف أولًا.', 'No students of {} were found.': 'لم يتم العثور على طلاب من {}.',
    'Reading pages {} to {} of {}...': 'جارٍ قراءة الصفحات من {1} إلى {2} من {3}...', 'the photo': 'الصورة', 'Reading {}...': 'جارٍ قراءة {}...',
    'The sheet says Week {}. Check the week before you save.': 'الكشف مكتوب عليه الأسبوع {}. راجع الأسبوع قبل الحفظ.',
    'found by name: check it': 'تم العثور عليه بالاسم: راجعه', 'already present': 'حاضر بالفعل', 'no ID': 'بدون رقم', '· page {}': '· صفحة {}', 'page {}': 'صفحة {}',
    'Choose who it is...': 'اختر من هو...', 'Choose a student...': 'اختر طالبًا...', 'read twice': 'قُرئ مرتين', 'Gemini read': 'قرأ Gemini', 'to save as present in {}': 'للحفظ كحضور في {}',
    'Handwriting can be misread: look at the orange and red lines against the paper. Untick anyone who should not be saved.': 'قد يُقرأ خط اليد خطأ: قارن الأسطر البرتقالية والحمراء بالورقة. ألغِ تعليم أي شخص لا يجب حفظه.',
    'On the paper (as Gemini read it)': 'في الورقة (كما قرأها Gemini)', '{} is already present in this week.': '{} حاضر بالفعل في هذا الأسبوع.',
    '{} saved as present in {}': function (n, w) { return 'تم حفظ ' + pl(n, N.st) + ' كحضور في ' + w; },
    'Fill the university sheet': 'ملء شيت الجامعة',
    'Upload the university\'s Excel file as it is. Every student is found by ID, the site writes section attendance (1 for present or excused) and the marks you choose, and you download the same file back, with its look untouched.': 'ارفع ملف إكسل الخاص بالجامعة كما هو. يتم العثور على كل طالب برقمه، ويكتب الموقع حضور السكشن (1 للحاضر أو بعذر) والدرجات التي تختارها، ثم تنزّل نفس الملف بنفس شكله تمامًا.',
    'University Excel file': 'ملف إكسل الجامعة', 'Fill and download': 'ملء وتنزيل',
    'No sheet with an "ID" column was found in this file.': 'لم يتم العثور في هذا الملف على ورقة فيها عمود "ID".', 'Leave as it is': 'اتركه كما هو',
    'Total (from the site)': 'المجموع (من الموقع)', 'Attendance Section W1 to W{}': 'Attendance Section W1 to W{}',
    'is filled from the section weeks (week 7, the midterm week, is left out).': 'يُملأ من أسابيع السكشن (الأسبوع 7، أسبوع الميدترم، لا يُحسب).',
    'Choose what goes in the other columns:': 'اختر ما يوضع في باقي الأعمدة:',
    'sheets ({}).': 'أوراق ({}).', 'Column in the university sheet': 'العمود في شيت الجامعة', 'Filled with': 'يُملأ بـ',
    'Also replace cells that already have a different value (otherwise only empty cells are filled)': 'استبدل أيضًا الخلايا التي فيها قيمة مختلفة (وإلا تُملأ الخلايا الفارغة فقط)',
    'cells kept as they were (they had another value)': 'خلايا تُركت كما هي (كان فيها قيمة أخرى)', 'IDs in the sheet are not in the site': 'أرقام في الشيت ليست في الموقع',
    'students of the site are not in the sheet': 'طلاب في الموقع ليسوا في الشيت', 'Not in the site: {}': 'ليسوا في الموقع: {}', 'cells filled': 'خلايا تم ملؤها',
    'students found': 'طلاب تم العثور عليهم', 'student name': 'اسم الطالب', 'student id': 'رقم الطالب',

    /* gradebook */
    'A mark is out of range. Fix the red cell.': 'توجد درجة خارج النطاق. صحّح الخلية الحمراء.',
    '{} not saved yet ({}). They are kept on this device and saved when it works again.': '{1} لم تُحفظ بعد ({2}). محفوظة على هذا الجهاز وستُحفظ عندما يعود الاتصال.',
    '{} saving in a moment...': '{} سيتم حفظها بعد لحظة...', 'All marks saved automatically ✓': 'كل الدرجات حُفظت تلقائيًا ✓', 'All marks saved': 'كل الدرجات محفوظة',
    'Every mark of the course in one table. Type in any box: it saves on its own, and Enter goes down to the next student.': 'كل درجات المادة في جدول واحد. اكتب في أي خانة: تُحفظ تلقائيًا، وEnter ينقلك للطالب التالي.',
    '{} from last time were not saved. Saving them now.': '{} من المرة السابقة لم تُحفظ. جارٍ حفظها الآن.',
    'No courses yet. Upload a course Excel sheet first.': 'لا توجد مواد بعد. ارفع شيت إكسل للمادة أولًا.', 'Choose or clear every {} group': 'اختر أو ألغِ كل مجموعات {}',
    'no grade items yet': 'لا توجد بنود درجات بعد', ', no students yet': '، لا يوجد طلاب بعد', 'no students yet': 'لا يوجد طلاب بعد', '+ New course': '+ مادة جديدة',
    'Add its grade items (for example Quiz 1, Midterm, Final) and their full marks.': 'أضف بنود درجاتها (مثل Quiz 1 وMidterm وFinal) ودرجاتها النهائية.',
    '(or ask the TA of the groups to upload it)': '(أو اطلب من معيد المجموعات رفعه)', 'Upload the Excel sheet of its students{}.': 'ارفع شيت إكسل لطلابها{}.',
    'Upload the Excel sheet of its students': 'ارفع شيت إكسل لطلابها',
    'Set grade items': 'تحديد بنود الدرجات', 'Only the admin can add the grade items.': 'المسؤول فقط يستطيع إضافة بنود الدرجات.', '{} is ready.': '{} جاهزة.',
    '{} Then you can enter the marks of every group here.': '{} بعدها يمكنك رصد درجات كل مجموعة هنا.', 'Then you can enter the marks of every group here.': 'بعدها يمكنك رصد درجات كل مجموعة هنا.',
    'All {} groups': function (n) { return 'كل المجموعات (' + n + ')'; }, 'Clear': 'مسح', 'Edit grade items': 'تعديل بنود الدرجات', '{} hidden': '{} مخفية',
    'Att.': 'الحضور', 'Pick at least one group.': 'اختر مجموعة واحدة على الأقل.', 'Type a student ID (or its last digits), then Enter': 'اكتب رقم الطالب (أو آخر أرقامه)، ثم Enter',
    'Search a name': 'ابحث عن اسم', 'Columns': 'الأعمدة', 'Paste': 'لصق', 'Copy for Excel': 'نسخ لإكسل', 'Section attendance': 'حضور السكشن',
    'W1 to W12: 1 for present or excused, empty otherwise': 'من W1 إلى W12: ‏1 للحاضر أو بعذر، وفارغ غير ذلك', 'the mark columns shown, no names': 'أعمدة الدرجات الظاهرة، بدون أسماء',
    'Whole table': 'الجدول كاملًا', 'names, IDs, groups, attendance, marks and total': 'الأسماء والأرقام والمجموعات والحضور والدرجات والمجموع',
    'upload their Excel file, get it back filled': 'ارفع ملف الإكسل الخاص بهم، واستلمه مملوءًا', 'students · average total': 'طالب · متوسط المجموع',
    'Copied W1 to W12 of {} students. In Excel: first student\'s W1 cell, Paste Special, tick Skip blanks.': function (n) { return 'تم نسخ W1 إلى W12 لـ ' + pl(n, N.st) + '. في إكسل: خلية W1 لأول طالب، ثم Paste Special، وعلّم Skip blanks.'; },
    'Copied the {} mark columns shown, in the same student order.': function (n) { return 'تم نسخ ' + pl(n, N.co) + ' درجات ظاهرة، بنفس ترتيب الطلاب.'; },
    'Attendance /{}': 'الحضور /{}', 'Total /{}': 'المجموع /{}', 'Copied the whole table. Paste it in Excel or Google Sheets.': 'تم نسخ الجدول كاملًا. الصقه في إكسل أو Google Sheets.',
    'Type at least 3 digits.': 'اكتب 3 أرقام على الأقل.', 'No student shown has an ID ending in {}.': 'لا يوجد طالب ظاهر رقمه ينتهي بـ {}.',
    '{} students end in {}. Type more digits.': function (n, d) { return pl(n, N.st) + ' أرقامهم تنتهي بـ ' + d + '. اكتب أرقامًا أكثر.'; },
    'one column for each of': 'عمود لكل من', ', in this order': '، بهذا الترتيب', 'the mark of': 'درجة', 'Paste from Excel': 'لصق من إكسل',
    'Copy from Excel the student ID and then {}, and paste them here. One student on each line. An empty cell is left as it is.': 'انسخ من إكسل رقم الطالب ثم {}، والصقها هنا. طالب واحد في كل سطر. الخلية الفارغة تُترك كما هي.',
    'Fill the marks': 'ملء الدرجات', 'Nothing to fill. Each line needs an ID and a mark.': 'لا يوجد ما يُملأ. كل سطر يحتاج رقمًا ودرجة.',
    '{} mark filled': function () { return 'تم ملء درجة واحدة'; }, '{} marks filled': function (n) { return 'تم ملء ' + pl(n, N.mk); },
    'mark filled': 'درجة تم ملؤها', 'marks filled': 'درجات تم ملؤها', '{}. They save on their own.': '{}. تُحفظ تلقائيًا.',

    /* dashboard */
    'Attendance, grades, students at risk and teams.': 'الحضور والدرجات والطلاب المعرّضون للخطر والفرق.', 'No students yet.': 'لا يوجد طلاب بعد.',
    'average attendance': 'متوسط الحضور', 'students at risk': 'طلاب معرّضون للخطر', 'weeks with attendance': 'أسابيع فيها حضور', 'average total': 'متوسط المجموع',
    'Week {}: no attendance': 'الأسبوع {}: لا يوجد حضور', 'Week {}: {}% ({} of {})': 'الأسبوع {1}: {2}% ({3} من {4})',
    'Present or excused, out of the students marked that week. The dashed line is 75%.': 'الحاضرون أو بعذر، من الطلاب المرصودين في ذلك الأسبوع. الخط المتقطع هو 75%.',
    'Average total': 'متوسط المجموع', 'Press a group to see only that group.': 'اضغط على مجموعة لعرضها وحدها.', 'Average attendance': 'متوسط الحضور', 'At risk': 'معرّضون للخطر',
    'Grade distribution': 'توزيع الدرجات',
    'How many students have each total, out of {}. {} of {} students have marks.': function (m, a, b) { return 'عدد الطلاب عند كل مجموع، من ' + m + '. لدى ' + a + ' من ' + pl(b, N.st) + ' درجات.'; },
    'Item': 'البند', 'Out of': 'من', 'Average': 'المتوسط', 'Highest': 'الأعلى', 'Lowest': 'الأدنى', 'Copy names': 'نسخ الأسماء', 'Below 75%': 'أقل من 75%',
    'Missed {} in a row': function (n) { return 'غاب ' + inRow(n); }, 'Why': 'السبب', 'Nobody. Every student is at 75% or above.': 'لا أحد. كل الطلاب عند 75% أو أكثر.',
    'Students at risk ({})': 'الطلاب المعرّضون للخطر ({})',
    'Attendance below 75%, or absent 2 weeks or more in a row. Press a student to open their group.': 'حضور أقل من 75%، أو غياب أسبوعين متتاليين أو أكثر. اضغط على طالب لفتح مجموعته.',
    'Press a team to grade it.': 'اضغط على فريق لتقييمه.', 'Team': 'الفريق', 'Members': 'الأعضاء', 'Copied {} names.': function (n) { return 'تم نسخ ' + pl(n, N.nm) + '.'; },
    'Could not copy.': 'تعذّر النسخ.',

    /* assistant */
    'Attendance summary': 'ملخص الحضور', 'Who is at risk?': 'من المعرّض للخطر؟', 'Absent 2 weeks in a row': 'غائب أسبوعين متتاليين', 'Who was absent this week?': 'من غاب هذا الأسبوع؟',
    'Top 10 grades': 'أعلى 10 درجات', 'Open the dashboard': 'فتح لوحة المتابعة',
    'Hi {}! Ask me about attendance, grades, groups, teams or one student. Try a question below.': 'أهلًا {}! اسألني عن الحضور أو الدرجات أو المجموعات أو الفرق أو طالب معيّن. جرّب سؤالًا من الأسئلة بالأسفل.',
    'I can answer:': 'أستطيع الإجابة عن:', 'Attendance summary, for a course or a group': 'ملخص الحضور، لمادة أو مجموعة',
    'Who is at risk, absent in a row, absent in a week, most absent, never absent': 'من المعرّض للخطر، من غاب أسابيع متتالية، من غاب في أسبوع معيّن، الأكثر غيابًا، من لم يغب أبدًا',
    'Top or lowest grades, grades below a number, who has no mark for an item': 'أعلى أو أقل الدرجات، الدرجات تحت رقم معيّن، من ليس له درجة في بند',
    'A team by number or by its project name, a student name or ID': 'فريق برقمه أو باسم مشروعه، أو اسم طالب أو رقمه',
    'Take me to: dashboard, settings, a group, take attendance': 'خذني إلى: لوحة المتابعة، الإعدادات، مجموعة، أخذ الحضور',
    'Name a group to narrow it, for example "in P1". Then ask "and P2?".': 'اذكر مجموعة لتحديد السؤال، مثل "in P1". ثم اسأل "and P2?".',
    'Any time!': 'في أي وقت!', 'Opening the dashboard{}.': 'جارٍ فتح لوحة المتابعة{}.', 'Opening the dashboard.': 'جارٍ فتح لوحة المتابعة.', 'Opening your settings.': 'جارٍ فتح إعداداتك.',
    'Opening group {}. Press Show QR there.': 'جارٍ فتح مجموعة {}. اضغط «عرض QR» هناك.',
    'Opening Take attendance. Tick the groups in front of you and press Show one QR for all.': 'جارٍ فتح «أخذ الحضور». علّم المجموعات الموجودة أمامك واضغط «عرض QR واحد للكل».',
    'Opening group {}.': 'جارٍ فتح مجموعة {}.', 'Students with an ID containing {}': 'طلاب أرقامهم تحتوي على {}', 'Team {}: {}': 'فريق {1}: {2}', 'Role': 'الدور', 'Leader': 'القائد',
    'More than one team matches. Which one?': 'أكثر من فريق مطابق. أيّهم تقصد؟', 'I did not find a team with this name. The teams are:': 'لم أجد فريقًا بهذا الاسم. الفرق هي:',
    'Absent {} weeks or more in a row': function (n) { return 'غائب ' + inRow(n) + ' أو أكثر'; }, 'In a row': 'متتالية',
    'Which week? For example: who was absent in week 5': 'أي أسبوع؟ مثلًا: who was absent in week 5', 'Absent in week {}': 'غائب في الأسبوع {}', 'Never absent': 'لم يغب أبدًا',
    'Most absences': 'الأكثر غيابًا', 'Attendance below {}%': 'حضور أقل من {}%', 'No mark yet for {}': 'لا توجد درجة بعد في {}', 'Lowest {}': 'أقل {}', 'Highest {}': 'أعلى {}',
    'Summary': 'الملخص', 'at risk': 'معرّضون للخطر', 'average total of': 'متوسط المجموع من', 'Last week with attendance: week {}, {} present.': 'آخر أسبوع فيه حضور: الأسبوع {1}، {2} حاضر.',
    'Absent at least once': 'غاب مرة واحدة على الأقل', 'Students named "{}"': 'طلاب باسم "{}"', 'absent {} in a row': function (n) { return 'غائب ' + inRow(n); },
    'Open the assistant': 'فتح المساعد', 'Assistant (press / to open)': 'المساعد (اضغط / لفتحه)', 'Assistant': 'المساعد', 'New chat': 'محادثة جديدة', 'Speak': 'تحدّث',
    'Send': 'إرسال', 'Tally assistant': 'مساعد Tally', 'Answers from your own data, free': 'إجابات من بياناتك أنت، مجانًا', '{} · from your own data, free': '{} · من بياناتك أنت، مجانًا',
    'from your own data, free': 'من بياناتك أنت، مجانًا', 'Nobody. 🎉': 'لا أحد. 🎉', 'Open group {}': 'فتح مجموعة {}', 'Grade this team': 'تقييم هذا الفريق', 'Only': 'فقط',
    'Copied ✓': 'تم النسخ ✓', 'I did not get that 🤔 Try a question below, a student name or ID, or type "help".': 'لم أفهم ذلك 🤔 جرّب سؤالًا من الأسفل، أو اسم طالب أو رقمه، أو اكتب "ساعدني".',
    'Close the assistant': 'إغلاق المساعد', 'The microphone did not work. Allow it in the browser, or type.': 'الميكروفون لم يعمل. اسمح به في المتصفح، أو اكتب.',

    /* import attendance */
    'An Excel file with one tab per group: an': 'ملف إكسل فيه ورقة لكل مجموعة: عمود', 'column and': 'وأعمدة', 'to': 'إلى',
    'columns. P (or 1) is present, E is excused. Absent is not recorded, so it stays empty. Students already present are left as they are.': '. ‏P (أو 1) حاضر، وE بعذر. الغياب لا يُسجَّل فيبقى فارغًا. الطلاب الحاضرون بالفعل يُتركون كما هم.',
    'Import': 'استيراد', '{} marks to import.': function (n) { return pl(n, N.mk) + ' للاستيراد.'; }, 'Reading the file': 'جارٍ قراءة الملف', 'Could not read this file.': 'تعذّرت قراءة هذا الملف.',
    'No attendance found. Each tab needs an ID column and Week 1, Week 2... columns.': 'لم يتم العثور على حضور. كل ورقة تحتاج عمود ID وأعمدة Week 1 وWeek 2...',
    'Weeks to import': 'الأسابيع المراد استيرادها', 'Importing': 'جارٍ الاستيراد', 'students not in this course': 'طلاب ليسوا في هذه المادة',
    'marks in other TAs\' groups, skipped': 'درجات في مجموعات معيدين آخرين، تم تخطيها',
    'Not found in {}: {}. Add them to their group, then import again.': 'غير موجودين في {1}: {2}. أضفهم إلى مجموعتهم، ثم استورد مرة أخرى.',
    'marked present now': 'تم تسجيلهم حاضرين الآن', 'were already present': 'كانوا حاضرين بالفعل', 'Attendance imported.': 'تم استيراد الحضور.',
    'Upload an Excel sheet': 'رفع شيت إكسل', 'The course file: one tab per letter, and a row like': 'ملف المادة: ورقة لكل حرف، وصف مثل',
    'above each group. Every group in the file is read.': 'فوق كل مجموعة. تُقرأ كل المجموعات الموجودة في الملف.',
    '{} of {} groups selected, {} students.': function (a, b, s) { return 'تم اختيار ' + a + ' من ' + pl(b, N.gr) + '، ' + pl(s, N.st) + '.'; },
    'No groups found. Each student row needs a name and an ID, under a row like "A3 - Toqa".': 'لم يتم العثور على مجموعات. كل صف طالب يحتاج اسمًا ورقمًا، تحت صف مثل "A3 - Toqa".',
    'Groups you import become yours.': 'المجموعات التي تستوردها تصبح مجموعاتك.', 'Select all': 'تحديد الكل', 'Select none': 'إلغاء التحديد',
    'Skipped, they belong to other TAs: {}.': 'تم التخطي، تابعة لمعيدين آخرين: {}.',
    'Imported {} groups ({} new students).{}': function (g, s, x) { return 'تم استيراد ' + pl(g, N.gr) + ' (' + pl(s, ['طالب جديد', 'طالبين جدد', 'طلاب جدد', 'طالبًا جديدًا']) + ').' + x; },
    'Imported {} groups ({} new students).': function (g, s) { return 'تم استيراد ' + pl(g, N.gr) + ' (' + pl(s, ['طالب جديد', 'طالبين جدد', 'طلاب جدد', 'طالبًا جديدًا']) + ').'; },

    /* TAs */
    'Upload a course first, then choose it here. With no course chosen, the TA sees every course.': 'ارفع مادة أولًا، ثم اخترها هنا. إذا لم تختر مادة، يرى المعيد كل المواد.',
    'Courses this TA teaches': 'المواد التي يدرّسها هذا المعيد', 'The TA sees only these courses. Tick none to show every course.': 'يرى المعيد هذه المواد فقط. لا تعلّم أي مادة لإظهار كل المواد.',
    'Check the courses this TA asked for, then confirm the account.': 'راجع المواد التي طلبها هذا المعيد، ثم أكّد الحساب.', 'Choose the courses this TA works in.': 'اختر المواد التي يعمل فيها هذا المعيد.',
    'Confirm account': 'تأكيد الحساب', '{} can log in now.': '{} يستطيع تسجيل الدخول الآن.', 'Add a TA': 'إضافة معيد',
    'The account works right away. Send the TA their username and password.': 'الحساب يعمل فورًا. أرسل للمعيد اسم المستخدم وكلمة المرور.', 'Add': 'إضافة', 'TA added.': 'تمت إضافة المعيد.',
    'Use them the next time you log in.': 'استخدمهما في المرة القادمة التي تسجّل فيها الدخول.', 'Send them to the TA.': 'أرسلهما للمعيد.', 'Set a new username and password. {}': 'حدّد اسم مستخدم وكلمة مرور جديدين. {}',
    'Set a new username and password.': 'حدّد اسم مستخدم وكلمة مرور جديدين.',

    /* take attendance */
    '(this week)': '(هذا الأسبوع)', 'Next today:': 'التالي اليوم:', 'at': 'الساعة', 'in': 'في', 'in Room': 'في قاعة', 'From the schedule, now': 'من الجدول، الآن',
    'No section of yours now in the schedule. Tap the groups in the room.': 'لا يوجد سكشن لك الآن في الجدول. اضغط على المجموعات الموجودة في القاعة.',
    'Only my groups': 'مجموعاتي فقط', 'Show every group of {}': 'عرض كل مجموعات {}', 'Check-in is live': 'تسجيل الحضور مفتوح', 'Show QR →': 'عرض QR ←',
    'Another room? Pick its groups.': 'قاعة أخرى؟ اختر مجموعاتها.', 'Pick the groups in front of you and press Show QR.': 'اختر المجموعات الموجودة أمامك واضغط «عرض QR».',
    'Pick every {} group': 'اختر كل مجموعات {}', 'Minutes open': 'مدة الفتح بالدقائق',
    'The code on the screen changes every few seconds, so only students in the room can check in.': 'الرمز على الشاشة يتغير كل بضع ثوانٍ، فلا يسجّل الحضور إلا الطلاب الموجودون في القاعة.',
    'Show QR': 'عرض QR', 'Open for': 'مفتوح لمدة', 'Strict mode': 'الوضع الصارم', 'code changes every few seconds': 'الرمز يتغير كل بضع ثوانٍ',
    'One QR for all the groups you pick. Students of other groups can scan it too.': 'رمز QR واحد لكل المجموعات التي تختارها. يمكن لطلاب المجموعات الأخرى مسحه أيضًا.',
    'pick a group': 'اختر مجموعة', 'Search a name or ID': 'ابحث بالاسم أو الرقم', 'All weeks (summary)': 'كل الأسابيع (ملخص)', '+ Add a guest': '+ إضافة ضيف',
    '+ Add a student': '+ إضافة طالب', 'Mark everyone present': 'تسجيل الكل حاضرين', 'Flags this week': 'تنبيهات هذا الأسبوع', 'Add a guest': 'إضافة ضيف',
    'A student from another group of {} who is in your section without internet. They are marked present in their own group for {}.': 'طالب من مجموعة أخرى في {1} موجود في سكشنك بدون إنترنت. يُسجَّل حاضرًا في مجموعته لـ {2}.',
    '{} is already present this week in group {}.': '{1} حاضر بالفعل هذا الأسبوع في مجموعة {2}.', '{} (group {}) is marked present.': 'تم تسجيل {1} (مجموعة {2}) حاضرًا.',
    'Add a student': 'إضافة طالب',
    'A new student of group {}. To move a student from another group, remove them from there first (press their name, then Remove).': 'طالب جديد في مجموعة {}. لنقل طالب من مجموعة أخرى، أزله من هناك أولًا (اضغط على اسمه، ثم «إزالة»).',
    '{} is added to group {}.': 'تمت إضافة {1} إلى مجموعة {2}.',
    'Mark everyone in group{} present for {}? Excused students stay excused.': 'تسجيل كل من في المجموعة{1} حاضرين في {2}؟ الطلاب الذين بعذر يبقون بعذر.',
    'Everyone is present. Now mark the absent students.': 'الكل حاضر. الآن سجّل الطلاب الغائبين.', 'Check-in closed.': 'تم إغلاق تسجيل الحضور.',
    'Remove the mark: the square becomes empty': 'حذف العلامة: يصبح المربع فارغًا', 'chosen for {}': 'تم اختيارهم لـ {}', 'Groups {}': 'المجموعات {}',
    'Every week of the term, with each student\'s attendance %.': 'كل أسابيع الترم، مع نسبة حضور كل طالب.', 'for groups': 'للمجموعات',
    'Check-in is open for this week{}. Students scan the QR code below.': 'تسجيل الحضور مفتوح لهذا الأسبوع{}. يمسح الطلاب رمز QR بالأسفل.',
    'Check-in is open for this week. Students scan the QR code below.': 'تسجيل الحضور مفتوح لهذا الأسبوع. يمسح الطلاب رمز QR بالأسفل.',
    'Check-in is open now for': 'تسجيل الحضور مفتوح الآن لـ', 'Go to {}': 'الذهاب إلى {}', 'this week': 'هذا الأسبوع', 'Check in together with': 'تسجيل الحضور مع',
    'One QR and one code for all of them. Each student is marked in their own group.': 'رمز QR واحد وكود واحد لهم جميعًا. كل طالب يُسجَّل في مجموعته.',
    'Accept students from other groups': 'قبول طلاب من مجموعات أخرى', 'Show QR for {}': 'عرض QR لـ {}', 'Full ID or its last digits': 'الرقم كاملًا أو آخر أرقامه',
    'Random check': 'تحقق عشوائي', '+5 minutes': '+5 دقائق', 'Projector view': 'عرض البروجكتور', 'Close check-in': 'إغلاق تسجيل الحضور', 'Scan to check in': 'امسح لتسجيل الحضور',
    'No internet? Tell your TA your ID': 'لا يوجد إنترنت؟ أخبر معيدك برقمك', 'In the room': 'في القاعة', 'checked in': 'سجّلوا حضورهم',
    'No internet? Type the student\'s ID': 'لا يوجد إنترنت؟ اكتب رقم الطالب', 'Mark present': 'تسجيل حاضر', 'Just checked in': 'سجّلوا للتو',
    'Exit projector view': 'الخروج من عرض البروجكتور', 'Added 5 minutes.': 'تمت إضافة 5 دقائق.',
    'Close check-in now? Students who did not check in will be absent.': 'إغلاق تسجيل الحضور الآن؟ الطلاب الذين لم يسجّلوا سيُحسبون غائبين.',
    'More than one student ends in {}. Who is it?': 'أكثر من طالب رقمه ينتهي بـ {}. من المقصود؟', '✓ {} ({}) was already present.': '✓ {1} ({2}) كان حاضرًا بالفعل.',
    '✓ {} ({}) is marked present.': '✓ تم تسجيل {1} ({2}) حاضرًا.', 'Random check: are they here?': 'تحقق عشوائي: هل هم موجودون؟', 'Nobody checked in yet.': 'لم يسجّل أحد حضوره بعد.',
    'Not here': 'غير موجود', 'Removed': 'تمت الإزالة', 'other groups': 'مجموعات أخرى', 'Students from other groups are counted in their own groups.': 'طلاب المجموعات الأخرى يُحسبون في مجموعاتهم.',
    'From other groups': 'من مجموعات أخرى', 'Waiting for students': 'في انتظار الطلاب', 'Closes in {}': 'يُغلق بعد {}', 'changes in {}s': 'يتغير بعد {} ث',
    'same code for this session': 'نفس الكود لهذه الجلسة', 'P = present, E = excused, empty = not present or no check-in that week.': 'P = حاضر، E = بعذر، فارغ = غير حاضر أو لم يسجّل في ذلك الأسبوع.',
    'Press week squares to choose them, then mark them all at once. Press a week name to choose that week for everyone.': 'اضغط على مربعات الأسابيع لاختيارها، ثم سجّلها كلها مرة واحدة. اضغط على اسم أسبوع لاختياره للجميع.',
    'Choose {} for every student shown': 'اختر {} لكل الطلاب الظاهرين', 'Week {}: press to choose': 'الأسبوع {}: اضغط للاختيار',
    'Choose every week until week {} that is not present yet': 'اختر كل أسبوع حتى الأسبوع {} لم يُسجَّل فيه حضور بعد', 'Choose missing weeks': 'اختر الأسابيع الناقصة',
    'Choose a single week to see flags.': 'اختر أسبوعًا واحدًا لترى التنبيهات.', '{} is present in every week until week {}.': '{1} حاضر في كل الأسابيع حتى الأسبوع {2}.',
    'not checked in yet': 'لم يسجّل بعد', 'not present': 'غير حاضر', '{}: no check-in yet.': '{}: لم يسجّل حضوره بعد.', 'Time': 'الوقت', 'How': 'الطريقة', 'Status': 'الحالة',
    '{} present of {}': '{1} حاضر من {2}', 'Not yet': 'ليس بعد', 'None': 'لا يوجد', 'Could not copy. Try again.': 'تعذّر النسخ. حاول مرة أخرى.',
    'Grades of group {}. Type the marks: they save on their own. Enter moves to the next student.': 'درجات مجموعة {}. اكتب الدرجات: تُحفظ تلقائيًا. Enter ينقلك للطالب التالي.',
    'Attendance →': 'الحضور ←', 'Copy': 'نسخ', 'Section attendance (W1 to W12)': 'حضور السكشن (W1 إلى W12)',
    'Skip blanks': 'Skip blanks', ', so the empty cells keep what is already there.': '، حتى تحتفظ الخلايا الفارغة بما فيها بالفعل.',
    'No check-in that week. The outlined squares are week 7 (Midterm) and week 14 (Final). Hover a square to see the week.': 'لم يسجّل في ذلك الأسبوع. المربعات المحددة هي الأسبوع 7 (الميدترم) والأسبوع 14 (النهائي). مرّر على مربع لترى الأسبوع.',
    'highest total': 'أعلى مجموع', 'grade item': 'بند درجات', 'grade items': 'بنود درجات', 'No grade items yet. Press': 'لا توجد بنود درجات بعد. اضغط',
    'to add the quizzes, assignments and midterm of this course.': 'لإضافة الكويزات والتكليفات والميدترم لهذه المادة.',
    'No grade items yet. The admin adds the quizzes and assignments of this course.': 'لا توجد بنود درجات بعد. يضيف المسؤول كويزات وتكليفات هذه المادة.',
    'Copied. In Excel: first student\'s W1 cell, Paste Special, tick Skip blanks.': 'تم النسخ. في إكسل: خلية W1 لأول طالب، ثم Paste Special، وعلّم Skip blanks.',
    'Copied the grade columns, in the same student order.': 'تم نسخ أعمدة الدرجات، بنفس ترتيب الطلاب.',
    'Whole team': 'الفريق كله', 'row to give it to everyone, change any student after that. Marks save on their own.': 'لإعطائها للجميع، ثم غيّر درجة أي طالب بعد ذلك. الدرجات تُحفظ تلقائيًا.',
    'Each mark is saved in the student\'s own group, so it also shows on that group\'s grades page.': 'كل درجة تُحفظ في مجموعة الطالب نفسه، فتظهر أيضًا في صفحة درجات تلك المجموعة.',
    'No grade items yet. The admin adds them in the Courses tab (for example Project or Discussion).': 'لا توجد بنود درجات بعد. يضيفها المسؤول من تبويب «المواد» (مثل Project أو Discussion).',
    '{} for the whole team': '{} للفريق كله', 'Type here to give the same mark to everyone': 'اكتب هنا لإعطاء نفس الدرجة للجميع', 'Not your group': 'ليست مجموعتك',
    'These are the same for every group of this course. Renaming an item keeps its marks.': 'هذه البنود نفسها لكل مجموعات المادة. تغيير اسم البند يحتفظ بدرجاته.',
    'Attendance is worth (marks, 0 for none)': 'درجة الحضور (بالدرجات، 0 لعدم احتسابه)', 'Items, in the same order as the course sheet. Tick': 'البنود، بنفس ترتيب شيت المادة. علّم',
    'Done / not done': 'تم / لم يتم', 'for an item you only mark as done (like an assignment): a tick gives the full mark.': 'للبند الذي تسجّله فقط كمُنجز (مثل التكليف): العلامة تعطي الدرجة كاملة.',
    '+ Quiz': '+ كويز', '+ Assignment': '+ تكليف', '+ Midterm': '+ ميدترم', '+ Other': '+ أخرى', 'Full mark': 'الدرجة النهائية',
    'Tick: you mark it Done or not done, and Done gives the full mark': 'علامة: تسجّله «تم» أو «لم يتم»، و«تم» تعطي الدرجة كاملة', 'No items yet.': 'لا توجد بنود بعد.',
    'Midterm': 'الميدترم', 'Grade items saved.': 'تم حفظ بنود الدرجات.', 'Attendance and grades': 'الحضور والدرجات', 'Made By: Toqa Hamdy': 'تصميم وتنفيذ: تقى حمدي',

    /* messages from the database */
    '"{}" is written twice.': '"{}" مكتوب مرتين.', '{} is already in group {}.': '{1} موجود بالفعل في مجموعة {2}.',
    '{} is in this group. Mark them in the list below.': '{} في هذه المجموعة. سجّله من القائمة بالأسفل.', '{} is not on any group list of {}.': '{1} ليس في أي قائمة مجموعات في {2}.',
    '{}: {} must be a number.': '{1}: {2} يجب أن تكون رقمًا.', '{}: {} must be from 0 to {}.': '{1}: {2} يجب أن تكون من 0 إلى {3}.',
    'Check-in is closed. Mark the student in the list below.': 'تسجيل الحضور مغلق. سجّل الطالب من القائمة بالأسفل.', 'Choose a date.': 'اختر تاريخًا.',
    'Choose a username first.': 'اختر اسم مستخدم أولًا.', 'Choose a week from 1 to 14.': 'اختر أسبوعًا من 1 إلى 14.', 'Choose at least one group.': 'اختر مجموعة واحدة على الأقل.',
    'Choose the course.': 'اختر المادة.', 'Give "{}" a full mark bigger than 0.': 'أعطِ "{}" درجة نهائية أكبر من 0.', 'No present marks found in the file.': 'لا توجد علامات حضور في الملف.',
    'No student of {} has an ID ending in {}.': 'لا يوجد طالب في {1} رقمه ينتهي بـ {2}.', 'No students found for {}, group {}.': 'لا يوجد طلاب في {1}، مجموعة {2}.',
    'None of the students in the file are in {}. Choose the right course.': 'لا أحد من طلاب الملف موجود في {}. اختر المادة الصحيحة.', 'Only the admin can do this.': 'المسؤول فقط يستطيع فعل ذلك.',
    'Paste the students first: a name and an ID on each line.': 'الصق الطلاب أولًا: اسم ورقم في كل سطر.', 'Session not found.': 'الجلسة غير موجودة.',
    'Setup is already done. Log in.': 'تم الإعداد بالفعل. سجّل الدخول.', 'Status must be P, A or E.': 'الحالة يجب أن تكون P أو A أو E.', 'Student {} is not in group {}.': 'الطالب {1} ليس في مجموعة {2}.',
    'Student not found.': 'الطالب غير موجود.', 'The ID looks too short.': 'الرقم يبدو قصيرًا جدًا.', 'The current password is wrong.': 'كلمة المرور الحالية خاطئة.',
    'The file is too big. Import fewer weeks or groups at a time.': 'الملف كبير جدًا. استورد أسابيع أو مجموعات أقل في كل مرة.', 'The password must be at least 6 characters.': 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.',
    'The username must be 3 to 30 letters, numbers, dots or dashes, with no spaces.': 'اسم المستخدم يجب أن يكون من 3 إلى 30 حرفًا أو رقمًا أو نقطة أو شرطة، بدون مسافات.',
    'This ID is already in group {} of this course. Remove the student from there first.': 'هذا الرقم موجود بالفعل في مجموعة {} في هذه المادة. أزل الطالب من هناك أولًا.',
    'This TA was not found.': 'لم يتم العثور على هذا المعيد.', 'This course is not one of your courses. Ask the admin.': 'هذه المادة ليست من موادك. اسأل المسؤول.',
    'This does not look like a Gemini key. Copy it again from aistudio.google.com.': 'هذا لا يبدو مفتاح Gemini. انسخه مرة أخرى من aistudio.google.com.',
    'This group belongs to {}. Ask the admin to change it.': 'هذه المجموعة تابعة لـ {}. اطلب من المسؤول تغييرها.', 'This name already exists.': 'هذا الاسم موجود بالفعل.',
    'This name already has an account. Log in, or ask the admin.': 'هذا الاسم له حساب بالفعل. سجّل الدخول، أو اسأل المسؤول.',
    'This photo cannot be used. Choose a JPG or PNG image.': 'لا يمكن استخدام هذه الصورة. اختر صورة JPG أو PNG.', 'This username is taken. Choose another one.': 'اسم المستخدم هذا مستخدم بالفعل. اختر غيره.',
    'Too many requests are waiting. Ask the admin.': 'يوجد طلبات كثيرة في الانتظار. اسأل المسؤول.', 'Type the student ID, or at least its last 3 digits.': 'اكتب رقم الطالب، أو آخر 3 أرقام منه على الأقل.',
    'Type the student ID.': 'اكتب رقم الطالب.', 'Week {} does not exist.': 'الأسبوع {} غير موجود.', 'Write the TA name.': 'اكتب اسم المعيد.', 'Write the course and the group.': 'اكتب المادة والمجموعة.',
    'Write the course name.': 'اكتب اسم المادة.', 'Write the student name and ID.': 'اكتب اسم الطالب ورقمه.', 'Write your full name.': 'اكتب اسمك بالكامل.', 'Write your name.': 'اكتب اسمك.',
    'Wrong username or password.': 'اسم المستخدم أو كلمة المرور خاطئة.', 'You cannot remove yourself.': 'لا يمكنك إزالة نفسك.',
    'Your account is waiting for the admin to confirm it.': 'حسابك في انتظار تأكيد المسؤول.'
  };
  Object.assign(T, {
    /* single words the pages use as labels */
    'students': 'طلاب', 'student': 'طالب', 'groups': 'مجموعات', 'group': 'مجموعة', 'teams': 'فرق', 'team': 'فريق', 'courses': 'مواد', 'marks': 'درجات', 'mark': 'درجة',
    'saving': 'جارٍ الحفظ', 'saved': 'تم الحفظ', 'lines': 'أسطر', 'items': 'بنود', 'people': 'أشخاص', 'person': 'شخص', 'changes': 'تغييرات', 'requests': 'طلبات', 'request': 'طلب',
    'live': 'مباشر', 'section': 'سكشن', 'extra': 'إضافية', 'total': 'المجموع', 'all': 'الكل', 'you': 'أنت', 'You': 'أنت', 'more': 'المزيد', 'now': 'الآن', 'next': 'التالي',
    'Assignment': 'تكليف', 'Quiz': 'كويز', 'Project': 'مشروع', 'Bonus': 'إضافي', 'Follow-up': 'متابعة', 'waiting': 'في الانتظار',
    '{} min': '{} د', 'of {}': 'من {}', '{} items': function (n) { return pl(n, N.it); }, '({} items)': function (n) { return '(' + pl(n, N.it) + ')'; },
    '{} ({} items)': function (c, n) { return c + ' (' + pl(n, N.it) + ')'; }, '{} (no grade items yet)': '{} (لا توجد بنود درجات بعد)', '(no grade items yet)': '(لا توجد بنود درجات بعد)',
    '{} students, {} phones': function (s, p) { return pl(s, N.st) + '، ' + pl(p, ['هاتف واحد', 'هاتفين', 'هواتف', 'هاتفًا']); },
    'Admin, username {}': 'مسؤول، اسم المستخدم {}', 'TA, username {}': 'معيد، اسم المستخدم {}', 'photo, password, theme': 'الصورة، كلمة المرور، المظهر',
    '{} TAs': function (n) { return pl(n, N.ta); }, '{} TA': function (n) { return pl(n, N.ta); }, '{} TAs, {} waiting': function (n, w) { return pl(n, N.ta) + '، ' + w + ' في الانتظار'; },
    'TAs ({})': 'المعيدون ({})', 'TAs ({}), {} waiting': 'المعيدون ({1})، {2} في الانتظار', 'TAs': 'المعيدون',
    '{} TA · {} groups': function (t, g) { return pl(t, N.ta) + ' · ' + pl(g, N.gr); }, '{} TAs · {} groups': function (t, g) { return pl(t, N.ta) + ' · ' + pl(g, N.gr); },
    '{} · {} groups': function (a, g) { return a + ' · ' + pl(g, N.gr); },
    'From the schedule, now ({}):': 'من الجدول، الآن ({}):', '{} (Midterm)': '{} (الميدترم)', '{} (Final)': '{} (النهائي)', 'Midterm': 'الميدترم', 'Final exam': 'الامتحان النهائي',
    'everything you wrote': 'كل ما كتبته', 'your groups': 'مجموعاتك', 'all groups': 'كل المجموعات',
    '{} students in {}': function (n, x) { return pl(n, N.st) + ' في ' + x; }, '{} student in {}': function (n, x) { return pl(n, N.st) + ' في ' + x; },
    '{} of {} groups': function (a, b) { return a + ' من ' + pl(b, N.gr); }, '{} of {} students': function (a, b) { return a + ' من ' + pl(b, N.st); },
    ', {} missed': '، {} غياب', '{} missed': '{} غياب', '{} changes': function (n) { return pl(n, N.ch); }, 'changes by': 'تغييرات بواسطة',
    'The student (QR)': 'الطالب (QR)', 'with {}': 'مع {}', 'or': 'أو', '{} PM': '{} م', '{} AM': '{} ص',
    '{} groups, {} students': function (g, n) { return pl(g, N.gr) + '، ' + pl(n, N.st); },
    'Manual': 'يدويًا', 'Self': 'بنفسه', 'Manual, in group {} ({})': 'يدويًا، في مجموعة {1} ({2})', 'Manual, in group {}': 'يدويًا، في مجموعة {}', 'Manual ({})': 'يدويًا ({})',
    'Self, in group {}': 'بنفسه، في مجموعة {}', 'Attended group {} with {}': 'حضر مع مجموعة {1} عند {2}', 'Attended group {}': 'حضر مع مجموعة {}',
    '{}, {}: {}': '{1}، {2}: {3}', '. The admin confirms it.': '، ويؤكده المسؤول.',

    /* history lines */
    'checked in with the QR code in': 'سجّل حضوره برمز QR في', 'removed the attendance of': 'حذف حضور', 'removed the mark': 'حذف الدرجة',
    'gave': 'أعطى', 'in': 'في', 'for': 'لـ', 'of': 'من', 'from': 'من', 'changed': 'غيّر', 'marked': 'سجّل', 'was': 'كان', '(was {})': '(كان {})',
    'added {} students to the group': function (n) { return 'أضاف ' + pl(n, N.st) + ' إلى المجموعة'; },
    'uploaded {} groups with {} students': function (g, s) { return 'رفع ' + pl(g, N.gr) + ' فيها ' + pl(s, N.st); },
    'added the student {} ({})': 'أضاف الطالب {1} ({2})', 'removed the student {} ({})': 'أزال الطالب {1} ({2})', 'took the group as their own': 'أخذ المجموعة لنفسه',
    'changed the TA of the group to {}': 'غيّر معيد المجموعة إلى {}', 'changed the TA of the group to nobody': 'ترك المجموعة بدون معيد', 'deleted the group': 'حذف المجموعة',
    'set the term start to {}': 'حدّد بداية الترم: {}', 'set the term start to nothing': 'ألغى بداية الترم', 'removed the Gemini key': 'حذف مفتاح Gemini', 'saved a Gemini key': 'حفظ مفتاح Gemini',
    'opened the check-in of {} for group {}': 'فتح تسجيل الحضور لـ {1} لمجموعة {2}', 'opened the check-in of {} for groups {}': 'فتح تسجيل الحضور لـ {1} للمجموعات {2}',
    'added {} minutes to the check-in of {}': function (n, w) { return 'أضاف ' + pl(n, N.mi) + ' إلى تسجيل حضور ' + w; }, 'closed the check-in of {}': 'أغلق تسجيل حضور {}',
    'changed the grade items: attendance {}': 'غيّر بنود الدرجات: الحضور {}'
  });

  /* ---------- the translator ---------- */
  var PATS = [], CACHE = Object.create(null), MISSING = Object.create(null), OUTS = Object.create(null), AR_RE = /[\u0600-\u06FF]/;
  var rx = function (s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); };
  /* {} before a counted word (5 students, 3 of 11 groups, 80%) can only be a number, so "Course (ECE101) (4 items)" splits in the right place */
  var COUNTED = /\{\}(?=%| (students?|groups|items|weeks?|marks?|TAs?|names|photos|minutes|changes|phones|present|excused|missed|project teams|new students|cells|columns|of \{\} groups|of \{\} students|present of))/g;
  Object.keys(T).forEach(function (k) {
    if (k.indexOf('{}') < 0) return;
    var src = '^' + k.replace(COUNTED, '\u0002').split(/(\{\}|\u0002)/).map(function (x) { return x === '{}' ? '(.+?)' : x === '\u0002' ? '(\\d+(?:[.,]\\d+)?)' : rx(x); }).join('') + '$';
    PATS.push({ re: new RegExp(src), v: T[k], lit: k.replace(/\{\}/g, '').length });
    delete T[k];
  });
  PATS.sort(function (a, b) { return b.lit - a.lit; });
  /* a name or an English word inside an Arabic line keeps its own direction */
  var iso = function (s) { return /[A-Za-z]/.test(s) ? '⁨' + s + '⁩' : s; };
  var flip = function (s) { return s.replace(/→/g, '\u0001').replace(/←/g, '→').replace(/\u0001/g, '←'); };
  function fill(v, caps) {
    if (typeof v === 'function') return v.apply(null, caps);
    var i = 0; return v.replace(/\{(\d*)\}/g, function (m, d) { var c = caps[d ? d - 1 : i++]; return c == null ? '' : c; });
  }
  function part(c) { var t = /[A-Za-z]/.test(c) ? tr(c.trim(), 1) : null; return t == null ? iso(c) : (/^\s/.test(c) ? ' ' : '') + t; }
  function tr(s, quiet) {
    if (s in CACHE) return CACHE[s];
    if (OUTS[s]) return null; /* already ours */
    if (/^[A-Z]{1,4}\d*$/.test(s) && s !== 'TA' && s !== 'ID') return null; /* group names and initials */
    var r = null, m, i;
    if (Object.prototype.hasOwnProperty.call(T, s)) r = T[s];
    if (r == null) for (i = 0; i < PATS.length; i++) { m = s.match(PATS[i].re); if (m) { r = fill(PATS[i].v, m.slice(1).map(part)); break; } }
    /* "Week 5 · Room 3": each piece on its own */
    if (r == null && /\s·\s|^·\s/.test(s)) {
      var bits = s.split(/(\s*·\s*)/), any = false;
      bits = bits.map(function (b) { if (/^\s*·\s*$/.test(b) || !/[A-Za-z]/.test(b)) return b; var t = tr(b.trim(), 1); if (t == null) return iso(b); any = true; return t; });
      if (any) r = bits.join('');
    }
    /* "Grades →", "(this week)", "Name:" and the like */
    if (r == null && (m = s.match(/^([(\[«"“+•–—-]*\s*)(.*?)(\s*[)\]»"”:.,;!?…→←]*)$/)) && (m[1] || m[3]) && m[2] && /[A-Za-z]/.test(m[2])) {
      var t = tr(m[2]); if (t != null) r = flip(m[1]) + t + flip(m[3]).replace(/\?/g, '؟').replace(/,/g, '،').replace(/;/g, '؛');
    }
    /* several sentences: each one on its own */
    if (r == null && /[.?!:]\s+\S/.test(s)) {
      var ss = s.split(/(?<=[.?!:])\s+/), ok = 0;
      ss = ss.map(function (x) { var t = tr(x, 1); if (t != null) { ok++; return t; } return x; });
      if (ok) r = ss.join(' ');
    }
    if (r != null) r = String(r); else if (!quiet && !AR_RE.test(s)) MISSING[s] = 1;
    CACHE[s] = r; return r;
  }
  function trAny(v) {
    if (!v || !/[A-Za-z]/.test(v)) return v;
    var lead = v.match(/^\s*/)[0], tail = v.match(/\s*$/)[0], core = v.trim().replace(/\s+/g, ' ');
    var t = tr(core); if (t == null) return v; t = lead + t + tail; OUTS[t] = OUTS[t.trim()] = 1; return t;
  }

  /* ---------- the page ---------- */
  var SKIP = /^(SCRIPT|STYLE|TEXTAREA|CODE|PRE|NOSCRIPT)$/;
  var ATTRS = ['title', 'placeholder', 'aria-label', 'alt'];
  var seen = new WeakMap();
  /* a person's initials in a round photo, a course badge: never words */
  var BADGE = /(^|\s)([\w-]*-av|gbadge|cbadge|lbadge|letter-big|q-letter)(\s|$)/;
  function skip(el) { for (var d = 0; el && el.nodeType === 1; el = el.parentNode, d++) { if (SKIP.test(el.tagName) || el.isContentEditable || el.hasAttribute('data-notr') || (d < 2 && BADGE.test(el.className || ''))) return true; } return false; }
  function text(n) {
    var v = n.nodeValue; if (seen.get(n) === v) return;
    if (!/[A-Za-z→←]/.test(v) || skip(n.parentNode)) { seen.set(n, v); return; }
    var t = /[A-Za-z]/.test(v) ? trAny(v) : flip(v);
    seen.set(n, t); if (t !== v) n.nodeValue = t;
  }
  function attrs(el) {
    if (el.nodeType !== 1 || el.hasAttribute('data-notr')) return;
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i], v = el.getAttribute(a); if (v && /[A-Za-z]/.test(v)) { var t = trAny(v); if (t !== v) el.setAttribute(a, t); }
    }
    if (el.tagName === 'INPUT' && /^(button|submit|reset)$/i.test(el.type) && /[A-Za-z]/.test(el.value)) { var tv = trAny(el.value); if (tv !== el.value) el.value = tv; }
  }
  function walk(root) {
    if (root.nodeType === 3) return text(root);
    if (root.nodeType !== 1 && root.nodeType !== 11) return;
    if (root.nodeType === 1) { if (skip(root)) return; attrs(root); }
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), n; while ((n = w.nextNode())) text(n);
    if (root.querySelectorAll) { var els = root.querySelectorAll('[title],[placeholder],[aria-label],[alt],input[type=button],input[type=submit]'); for (var i = 0; i < els.length; i++) attrs(els[i]); }
  }
  new MutationObserver(function (list) {
    for (var i = 0; i < list.length; i++) {
      var m = list[i];
      if (m.type === 'childList') for (var j = 0; j < m.addedNodes.length; j++) walk(m.addedNodes[j]);
      else if (m.type === 'characterData') text(m.target);
      else if (m.type === 'attributes') attrs(m.target);
    }
  }).observe(de, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS.concat('value') });

  /* the browser's own boxes */
  ['alert', 'confirm', 'prompt'].forEach(function (k) {
    var f = window[k]; if (!f) return;
    window[k] = function (msg) { var a = [].slice.call(arguments); a[0] = trAny(String(msg == null ? '' : msg)); return f.apply(window, a); };
  });

  window.TG_AR = { tr: trAny, missing: function () { return Object.keys(MISSING); }, pl: pl, N: N };
})();
