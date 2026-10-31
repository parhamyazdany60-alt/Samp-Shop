import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ====================== تنظیمات ======================
const supabaseUrl = 'https://ejtiddwdcvzdetgixvwn.supabase.co';
const supabaseKey = 'sb_publishable_t29fLJH6W6rPcdgffXh95w_qTkqUrwr';
// ایمیل ساختگی برای ورود با اسم (هیچ ایمیلی فرستاده نمی‌شه)
const emailDomain = 'gmail.com';

SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Samp Shop',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const Gate(),
    );
  }
}

// ====================== ابزارها ======================
String emailFor(String name) {
  final n = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final h = sha256.convert(utf8.encode(n)).toString().substring(0, 40);
  return '$h@$emailDomain';
}

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

String fa2en(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var o = s;
  for (var i = 0; i < 10; i++) {
    o = o.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return o.replaceAll('٫', '.').replaceAll(',', '').replaceAll('٬', '');
}

String num3(dynamic n) {
  final s = (n as num).toStringAsFixed(0);
  return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

String errMsg(Object e) {
  String m;
  if (e is PostgrestException) {
    m = e.message;
  } else if (e is AuthException) {
    m = e.message;
  } else {
    m = e.toString();
  }
  final l = m.toLowerCase();
  if (l.contains('invalid login')) return 'اسم یا رمز اشتباهه';
  if (l.contains('already registered') || l.contains('database error saving')) {
    return 'این اسم قبلاً گرفته شده';
  }
  if (l.contains('password should')) return 'رمز باید حداقل ۶ حرف باشه';
  if (l.contains('row-level security')) {
    return 'دسترسی ندارید (ممکنه اکانتتون مسدود شده باشه)';
  }
  if (l.contains('duplicate key')) return 'قبلاً انجام شده';
  if (l.contains('invalid') && l.contains('email')) {
    return 'ثبت‌نام با این اسم ممکن نیست، اسم دیگه‌ای امتحان کن';
  }
  if (l.contains('socket') ||
      l.contains('failed host lookup') ||
      l.contains('clientexception')) {
    return 'اتصال به سرور برقرار نشد';
  }
  return m;
}

Future<void> openUrl(String u) async {
  try {
    await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

String imgUrl(String path) => db.storage.from('listing-images').getPublicUrl(path);

String? firstImage(Map l) {
  final raw = l['listing_images'];
  if (raw is! List || raw.isEmpty) return null;
  final imgs = List<Map>.from(raw);
  imgs.sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));
  return imgUrl(imgs.first['path'] as String);
}

String priceText(Map l) {
  final p = <String>[];
  if (l['price_real'] != null) p.add('${num3(l['price_real'])} تومان');
  if (l['price_game'] != null) p.add('${num3(l['price_game'])} پول بازی');
  return p.join('  |  ');
}

Future<String?> askText(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        maxLength: 500,
        maxLines: 3,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text('ثبت'),
        ),
      ],
    ),
  );
}

// ====================== فیلدهای هر دسته ======================
class F {
  final String key, label, type; // text, digits, num, bool, enum, enumn
  final num? min, max;
  final Map<String, String>? opts;
  final bool req;
  const F(this.key, this.label, this.type,
      {this.min, this.max, this.opts, this.req = true});
}

const cityOpts = {'1': 'شهر ۱', '2': 'شهر ۲', '3': 'شهر ۳'};

const vehicleFields = <F>[
  F('full_name', 'اسم کامل', 'text'),
  F('engine', 'Engine (۱ تا ۴)', 'num', min: 1, max: 4),
  F('turbo', 'Turbo (۱ تا ۴)', 'num', min: 1, max: 4),
  F('suspension', 'Suspension (۱ تا ۴)', 'num', min: 1, max: 4),
  F('transmission', 'Transmission (۱ تا ۴)', 'num', min: 1, max: 4),
  F('plate', 'پلاک (فقط عدد)', 'digits'),
  F('top_speed_stock', 'حداکثر سرعت بدون تقویت', 'num', min: 1, max: 1000),
  F('top_speed_tuned', 'حداکثر سرعت بعد تقویت', 'num', min: 1, max: 1000),
  F('premium', 'پرمیوم', 'bool'),
  F('starter', 'Starter condition (۱ تا ۱۰۰)', 'num', min: 1, max: 100),
  F('battery', 'وضعیت باتری (۱ تا ۱۰۰)', 'num', min: 1, max: 100),
  F('fuel_system', 'وضعیت سیستم سوخت (۱ تا ۱۰۰)', 'num', min: 1, max: 100),
  F('clutch', 'وضعیت کلاچ (۱ تا ۱۰۰)', 'num', min: 1, max: 100),
  F('engine_health', 'وضعیت موتور (۱ تا ۱۰۰)', 'num', min: 1, max: 100),
];

List<F> fieldsFor(String code, Map<String, dynamic> v) {
  switch (code) {
    case 'phone':
      return const [F('number', 'شماره (فقط عدد)', 'digits')];
    case 'money':
      return const [
        F('amount_million', 'مقدار (به میلیون)', 'num', min: 1, max: 1000000)
      ];
    case 'car':
    case 'bike':
      return vehicleFields;
    case 'house':
      final maxW = {'nope': 4, 'C': 6, 'B': 8, 'A': 10}[v['class']] ?? 4;
      final list = <F>[
        const F('house_id', 'آیدی خونه', 'num', min: 0, max: 100000000),
        const F('class', 'کلس خونه', 'enum', opts: {
          'nope': 'Class nope',
          'C': 'Class C',
          'B': 'Class B',
          'A': 'Class A'
        }),
        const F('elite', 'نخبه شده', 'bool'),
        const F('has_basement', 'زیرزمین دارد', 'bool'),
        const F('has_workroom', 'اتاق کار دارد', 'bool'),
      ];
      if (v['has_workroom'] == true) {
        list.addAll([
          F('workers_count', 'تعداد کارگر (۱ تا $maxW)', 'num', min: 1, max: maxW),
          F('workers_lvl1', 'تعداد کارگر لول ۱', 'num', min: 0, max: maxW),
          F('workers_lvl2', 'تعداد کارگر لول ۲', 'num', min: 0, max: maxW),
          F('workers_lvl3', 'تعداد کارگر لول ۳', 'num', min: 0, max: maxW),
        ]);
      }
      list.add(const F('miners_count', 'تعداد ماینر (۰ = ندارد)', 'num',
          min: 0, max: 100000, req: false));
      final mc = v['miners_count'];
      if (mc is num && mc > 0) {
        list.addAll([
          F('miners_lvl1', 'تعداد ماینر لول ۱', 'num', min: 0, max: mc),
          F('miners_lvl2', 'تعداد ماینر لول ۲', 'num', min: 0, max: mc),
          F('miners_lvl3', 'تعداد ماینر لول ۳', 'num', min: 0, max: mc),
        ]);
      }
      list.addAll(const [
        F('city', 'منطقه (شهر)', 'enumn', opts: cityOpts),
        F('area', 'جای خونه توی شهر', 'enum', opts: {
          'upper': 'بالا شهر',
          'middle': 'وسط شهر',
          'lower': 'پایین شهر'
        }),
        F('seaside', 'کنار دریا', 'bool'),
        F('great_view', 'نمای خفن', 'bool'),
      ]);
      return list;
    case 'business':
      return const [
        F('business_id', 'آیدی بیزنس', 'num', min: 0, max: 100000000),
        F('city', 'منطقه (شهر)', 'enumn', opts: cityOpts),
        F('business_type', 'نوع بیزنس (مثلاً پمپ بنزین، سوپرمارکت)', 'text'),
      ];
    case 'item':
      return const [
        F('item_name', 'اسم آیتم', 'text'),
        F('item_use', 'کاربرد آیتم', 'text'),
      ];
    case 'skin':
      return const [
        F('skin_id', 'آیدی اسکین', 'num', min: 0, max: 100000),
        F('skin_condition', 'وضعیت اسکین (۱ تا ۱۰۰)', 'num', min: 1, max: 100),
        F('premium', 'پرمیوم', 'bool'),
      ];
    case 'accessory':
      return const [
        F('accessory_condition', 'وضعیت اکسسوری (۱ تا ۱۰۰)', 'num', min: 1, max: 100),
        F('premium', 'پرمیوم', 'bool'),
      ];
    case 'bug':
      return const [
        F('bug_about', 'باگ مربوط به چیه؟ (مثلاً کازینو)', 'text'),
        F('bug_description', 'باگ چیکار می‌کنه؟', 'text'),
      ];
    default:
      return const [];
  }
}

String fieldValueText(F f, dynamic v) {
  if (f.type == 'bool') return v == true ? 'بله' : 'خیر';
  if (f.opts != null) return f.opts![v.toString()] ?? v.toString();
  return v.toString();
}

// ====================== ورود ======================
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, snap) {
        final session = snap.data?.session ?? db.auth.currentSession;
        return session == null ? const AuthPage() : const Shell();
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final name = TextEditingController();
  final pass = TextEditingController();
  bool register = false, busy = false, hide = true;

  Future<void> submit() async {
    final n = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final p = pass.text;
    if (n.length < 3 || n.length > 24) {
      snack(context, 'اسم باید ۳ تا ۲۴ حرف باشه');
      return;
    }
    if (p.length < 6) {
      snack(context, 'رمز باید حداقل ۶ حرف باشه');
      return;
    }
    setState(() => busy = true);
    try {
      if (register) {
        await db.auth.signUp(
            email: emailFor(n), password: p, data: {'username': n});
      } else {
        await db.auth.signInWithPassword(email: emailFor(n), password: p);
      }
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.storefront, size: 72, color: Colors.teal),
                const SizedBox(height: 8),
                const Text('Samp Shop',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(register ? 'ساخت حساب جدید' : 'ورود',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'اسم', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 6),
                const Text(
                  '(اسم بازی خودتون رو نزنید چون پول گیم هم اینجا خرید و فروش میشه ممکنه بعضیا شات بگیرن بدن دست ادمینا)',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pass,
                  obscureText: hide,
                  decoration: InputDecoration(
                    labelText: 'رمز',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => hide = !hide),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(register ? 'ثبت‌نام' : 'ورود'),
                ),
                TextButton(
                  onPressed: () => setState(() => register = !register),
                  child: Text(register
                      ? 'حساب دارم، ورود'
                      : 'حساب ندارم، ثبت‌نام'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ====================== صفحه اصلی با نوار پایین ======================
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int idx = 0, refresh = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(key: ValueKey('h$refresh')),
      CreatePage(
        key: ValueKey('c$refresh'),
        onDone: () => setState(() {
          idx = 0;
          refresh++;
        }),
      ),
      const ChatsPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      body: IndexedStack(index: idx, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'خانه'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline), label: 'ثبت آگهی'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'چت‌ها'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'من'),
        ],
      ),
    );
  }
}

// ====================== کارت آگهی ======================
class ListingCard extends StatelessWidget {
  final Map l;
  final VoidCallback onTap;
  final Widget? trailing;
  const ListingCard({super.key, required this.l, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final img = firstImage(l);
    final cat = (l['categories'] is Map) ? l['categories']['name'] : '';
    final status = l['status'];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: img == null
                  ? Container(
                      color: Colors.teal.shade50,
                      child: const Icon(Icons.image_not_supported_outlined))
                  : Image.network(img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(priceText(l),
                        style: const TextStyle(color: Colors.teal)),
                    const SizedBox(height: 4),
                    Text(
                        '$cat${status != null && status != 'active' ? '  •  ${status == 'sold' ? 'فروخته شد' : 'حذف شده'}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

const listingSelect =
    '*, listing_images(path, sort_order), categories(name, code), profiles(username)';

// ====================== خانه ======================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> cats = [], items = [];
  int? cat;
  String search = '';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      final c = await db.from('categories').select().order('sort_order');
      cats = List<Map<String, dynamic>>.from(c);
    } catch (_) {}
    if (!mounted) return;
    await load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var q = db.from('listings').select(listingSelect).eq('status', 'active');
      if (cat != null) q = q.eq('category_id', cat!);
      if (search.isNotEmpty) q = q.ilike('title', '%$search%');
      final r = await q.order('created_at', ascending: false).limit(60);
      items = List<Map<String, dynamic>>.from(r);
    } catch (e) {
      error = errMsg(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Samp Shop')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: TextField(
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'جستجو توی آگهی‌ها',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (s) {
                search = s.trim();
                load();
              },
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: const Text('همه'),
                    selected: cat == null,
                    onSelected: (_) {
                      cat = null;
                      load();
                    },
                  ),
                ),
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text(c['name']),
                      selected: cat == c['id'],
                      onSelected: (_) {
                        cat = c['id'] as int;
                        load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: loading
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: CircularProgressIndicator())
                    ])
                  : error != null
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Center(child: Text(error!)),
                        ])
                      : items.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 120),
                              Center(child: Text('آگهی‌ای پیدا نشد')),
                            ])
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (_, i) => ListingCard(
                                l: items[i],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          DetailPage(id: items[i]['id'])),
                                ).then((_) => load()),
                              ),
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== جزئیات آگهی ======================
class DetailPage extends StatefulWidget {
  final String id;
  const DetailPage({super.key, required this.id});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Map<String, dynamic>? l;
  Map<String, dynamic>? rating;
  bool loading = true, fav = false, isAdmin = false;
  String? error;
  final me = db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await db
          .from('listings')
          .select(
              '*, listing_images(path, sort_order), categories(name, code), profiles(id, username, game_phone), servers(name)')
          .eq('id', widget.id)
          .single();
      l = r;
      final sid = r['user_id'];
      rating = await db
          .from('seller_ratings')
          .select()
          .eq('seller_id', sid)
          .maybeSingle();
      final f = await db
          .from('favorites')
          .select()
          .eq('user_id', me)
          .eq('listing_id', widget.id)
          .maybeSingle();
      fav = f != null;
      final p =
          await db.from('profiles').select('is_admin').eq('id', me).single();
      isAdmin = p['is_admin'] == true;
    } catch (e) {
      error = errMsg(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> toggleFav() async {
    try {
      if (fav) {
        await db
            .from('favorites')
            .delete()
            .eq('user_id', me)
            .eq('listing_id', widget.id);
      } else {
        await db.from('favorites').insert({'user_id': me, 'listing_id': widget.id});
      }
      setState(() => fav = !fav);
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  Future<void> startChat() async {
    try {
      final ex = await db
          .from('conversations')
          .select('id')
          .eq('listing_id', widget.id)
          .eq('buyer_id', me)
          .maybeSingle();
      String cid;
      if (ex != null) {
        cid = ex['id'] as String;
      } else {
        final r = await db
            .from('conversations')
            .insert({
              'listing_id': widget.id,
              'buyer_id': me,
              'seller_id': l!['user_id']
            })
            .select('id')
            .single();
        cid = r['id'] as String;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatPage(cid: cid, title: l!['title'] ?? 'چت')),
      );
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  Future<void> rate() async {
    int stars = 5;
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('امتیاز به فروشنده'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(i <= stars ? Icons.star : Icons.star_border,
                          color: Colors.amber),
                      onPressed: () => set(() => stars = i),
                    ),
                ],
              ),
              TextField(
                controller: c,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'نظر (اختیاری)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('بستن')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ثبت')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await db.from('reviews').insert({
        'reviewer_id': me,
        'seller_id': l!['user_id'],
        'rating': stars,
        'comment': c.text.trim().isEmpty ? null : c.text.trim(),
      });
      if (mounted) snack(context, 'امتیاز ثبت شد');
      load();
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  Future<void> report() async {
    final reason = await askText(context, 'گزارش کلاهبرداری یا تخلف', 'دلیل گزارش');
    if (reason == null) return;
    if (reason.length < 3) {
      if (mounted) snack(context, 'دلیل رو بنویس');
      return;
    }
    try {
      await db.from('reports').insert({
        'reporter_id': me,
        'listing_id': widget.id,
        'reported_user_id': l!['user_id'],
        'reason': reason,
      });
      if (mounted) snack(context, 'گزارش ثبت شد');
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  Future<void> markSold() async {
    try {
      await db.from('listings').update({'status': 'sold'}).eq('id', widget.id);
      load();
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  Future<void> remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف آگهی؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('نه')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('listings').delete().eq('id', widget.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  Future<void> ban() async {
    try {
      await db
          .from('profiles')
          .update({'is_banned': true}).eq('id', l!['user_id']);
      if (mounted) snack(context, 'کاربر بن شد');
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  Widget contactTile(String label, dynamic id, {String? url}) {
    if (id == null || id.toString().isEmpty) return const SizedBox.shrink();
    final s = id.toString();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('$label: $s'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: s));
              snack(context, 'کپی شد');
            },
          ),
          if (url != null)
            IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => openUrl(url)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    final m = l;
    if (m == null) {
      return Scaffold(
          appBar: AppBar(), body: Center(child: Text(error ?? 'آگهی پیدا نشد')));
    }
    final owner = m['user_id'] == me;
    final code = (m['categories']['code'] ?? '') as String;
    final seller = (m['profiles'] ?? {}) as Map;
    final details = Map<String, dynamic>.from((m['details'] ?? {}) as Map);
    final fs = fieldsFor(code, details);
    final desc = (m['description'] ?? '') as String;
    final urls = RegExp(r'https?://[^\s]+')
        .allMatches(desc)
        .map((x) => x.group(0)!)
        .toList();
    final rawImgs = (m['listing_images'] ?? []) as List;
    final imgs = List<Map>.from(rawImgs)
      ..sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));
    final sold = m['status'] != 'active';

    return Scaffold(
      appBar: AppBar(
        title: Text(m['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                color: fav ? Colors.red : null),
            onPressed: toggleFav,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          if (imgs.isNotEmpty)
            SizedBox(
              height: 260,
              child: PageView(
                children: [
                  for (final i in imgs)
                    Image.network(imgUrl(i['path'] as String),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image))),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sold)
                  Container(
                    padding: const EdgeInsets.all(6),
                    color: Colors.orange.shade100,
                    child: const Text('این آگهی دیگه فعال نیست'),
                  ),
                Text(m['title'] ?? '',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(priceText(m),
                    style: const TextStyle(fontSize: 18, color: Colors.teal)),
                const SizedBox(height: 4),
                Text(
                    '${m['categories']['name']}  •  ${(m['servers'] ?? {})['name'] ?? ''}',
                    style: const TextStyle(color: Colors.grey)),
                const Divider(height: 24),
                for (final f in fs)
                  if (details[f.key] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(flex: 5, child: Text(f.label)),
                          Expanded(
                              flex: 4,
                              child: Text(fieldValueText(f, details[f.key]),
                                  style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                if (desc.isNotEmpty) ...[
                  const Divider(height: 24),
                  SelectableText(desc),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final u in urls)
                        ActionChip(
                          avatar: const Icon(Icons.link, size: 16),
                          label: Text(u.length > 28 ? '${u.substring(0, 28)}...' : u),
                          onPressed: () => openUrl(u),
                        ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Text('فروشنده: ${seller['username'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(rating != null
                    ? '⭐ ${rating!['avg_rating']}  (${rating!['review_count']} نظر)'
                    : 'هنوز امتیازی نداره'),
                if ((seller['game_phone'] ?? '').toString().isNotEmpty)
                  contactTile('شماره تلفن بازی', seller['game_phone']),
                contactTile('روبیکا', m['rubika_id'],
                    url: m['rubika_id'] == null
                        ? null
                        : 'https://rubika.ir/${m['rubika_id'].toString().replaceFirst('@', '')}'),
                contactTile('تلگرام', m['telegram_id'],
                    url: m['telegram_id'] == null
                        ? null
                        : 'https://t.me/${m['telegram_id'].toString().replaceFirst('@', '')}'),
                contactTile('سروش', m['soroush_id']),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!owner)
                      FilledButton.icon(
                          onPressed: startChat,
                          icon: const Icon(Icons.chat),
                          label: const Text('چت با فروشنده')),
                    if (!owner)
                      OutlinedButton.icon(
                          onPressed: rate,
                          icon: const Icon(Icons.star_outline),
                          label: const Text('امتیاز به فروشنده')),
                    if (!owner)
                      OutlinedButton.icon(
                          onPressed: report,
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('گزارش کلاهبرداری')),
                    if (owner && !sold)
                      OutlinedButton(
                          onPressed: markSold, child: const Text('فروخته شد')),
                    if (owner || isAdmin)
                      OutlinedButton(
                          onPressed: remove, child: const Text('حذف آگهی')),
                    if (isAdmin && !owner)
                      OutlinedButton(
                          onPressed: ban, child: const Text('بن کردن فروشنده')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== ثبت آگهی ======================
class CreatePage extends StatefulWidget {
  final VoidCallback onDone;
  const CreatePage({super.key, required this.onDone});
  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  List<Map<String, dynamic>> cats = [], servers = [];
  Map<String, dynamic>? cat;
  int? serverId;
  String saleType = 'real';
  final vals = <String, dynamic>{};
  final title = TextEditingController(),
      desc = TextEditingController(),
      pReal = TextEditingController(),
      pGame = TextEditingController(),
      rub = TextEditingController(),
      tel = TextEditingController(),
      sor = TextEditingController();
  List<XFile> imgs = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      final c = await db.from('categories').select().order('sort_order');
      final s = await db.from('servers').select().eq('is_active', true);
      cats = List<Map<String, dynamic>>.from(c);
      servers = List<Map<String, dynamic>>.from(s);
      if (servers.isNotEmpty) serverId = servers.first['id'] as int;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void err(String m) => snack(context, m);

  Future<void> pick() async {
    final r = await ImagePicker().pickMultiImage(imageQuality: 70, maxWidth: 1280);
    if (r.isEmpty) return;
    setState(() => imgs = [...imgs, ...r].take(5).toList());
  }

  Future<void> submit() async {
    if (cat == null) {
      err('اول دسته رو انتخاب کن');
      return;
    }
    final code = cat!['code'] as String;
    final fs = fieldsFor(code, vals);
    final t = title.text.trim();
    if (t.length < 3 || t.length > 100) {
      err('عنوان باید ۳ تا ۱۰۰ حرف باشه');
      return;
    }
    if (serverId == null) {
      err('سروری پیدا نشد');
      return;
    }
    final details = <String, dynamic>{};
    for (final f in fs) {
      final v = vals[f.key];
      if (f.type == 'bool') {
        details[f.key] = v == true;
        continue;
      }
      if (v == null || (v is String && v.isEmpty)) {
        if (f.req) {
          err('«${f.label}» رو پر کن');
          return;
        }
        continue;
      }
      if (f.type == 'num' || f.type == 'enumn') {
        if (v is! num) {
          err('«${f.label}» باید عدد باشه');
          return;
        }
        if ((f.min != null && v < f.min!) || (f.max != null && v > f.max!)) {
          err('«${f.label}» باید بین ${f.min} و ${f.max} باشه');
          return;
        }
      }
      if (f.type == 'digits' && !RegExp(r'^[0-9]{1,15}$').hasMatch(v.toString())) {
        err('«${f.label}» باید فقط عدد باشه');
        return;
      }
      details[f.key] = v;
    }
    if (code == 'house') {
      num lv(String p) => (details['${p}1'] ?? 0) + (details['${p}2'] ?? 0) + (details['${p}3'] ?? 0);
      if (vals['has_workroom'] == true &&
          lv('workers_lvl') != details['workers_count']) {
        err('جمع کارگرهای لول ۱ و ۲ و ۳ باید برابر تعداد کارگر باشه');
        return;
      }
      final mc = details['miners_count'];
      if (mc is num && mc > 0 && lv('miners_lvl') != mc) {
        err('جمع ماینرهای لول ۱ و ۲ و ۳ باید برابر تعداد ماینر باشه');
        return;
      }
    }

    final sale = code == 'money' ? 'real' : saleType;
    int? pr, pg;
    if (sale != 'game') {
      pr = int.tryParse(fa2en(pReal.text).trim());
      if (pr == null || pr < 0) {
        err('قیمت به تومان رو درست وارد کن');
        return;
      }
    }
    if (sale != 'real') {
      pg = int.tryParse(fa2en(pGame.text).trim());
      if (pg == null || pg < 0) {
        err('قیمت به پول بازی رو درست وارد کن');
        return;
      }
    }
    final idRe = RegExp(r'^@?[A-Za-z0-9_.]{3,64}$');
    for (final x in [rub, tel, sor]) {
      final s = x.text.trim();
      if (s.isNotEmpty && !idRe.hasMatch(s)) {
        err('آیدی‌ها فقط حرف انگلیسی، عدد، _ و . داشته باشن (حداقل ۳ حرف)');
        return;
      }
    }
    String? nz(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

    setState(() => busy = true);
    String? listingId;
    try {
      final uid = db.auth.currentUser!.id;
      final row = await db
          .from('listings')
          .insert({
            'user_id': uid,
            'server_id': serverId,
            'category_id': cat!['id'],
            'title': t,
            'description': nz(desc),
            'sale_type': sale,
            'price_real': pr,
            'price_game': pg,
            'details': details,
            'rubika_id': nz(rub),
            'telegram_id': nz(tel),
            'soroush_id': nz(sor),
          })
          .select('id')
          .single();
      listingId = row['id'] as String;
      if (code != 'bug') {
        for (var i = 0; i < imgs.length; i++) {
          final x = imgs[i];
          final ext = x.path.split('.').last.toLowerCase();
          final mime = ext == 'png'
              ? 'image/png'
              : ext == 'webp'
                  ? 'image/webp'
                  : 'image/jpeg';
          final path = '$uid/$listingId/$i.${ext == 'png' || ext == 'webp' ? ext : 'jpg'}';
          await db.storage.from('listing-images').upload(path, File(x.path),
              fileOptions: FileOptions(contentType: mime, upsert: true));
          await db.from('listing_images').insert(
              {'listing_id': listingId, 'path': path, 'sort_order': i});
        }
      }
      if (mounted) snack(context, 'آگهی ثبت شد');
      widget.onDone();
      return;
    } catch (e) {
      if (listingId != null) {
        try {
          await db.from('listings').delete().eq('id', listingId);
        } catch (_) {}
      }
      if (mounted) err(errMsg(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Widget fieldWidget(F f, String code) {
    if (f.type == 'bool') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: vals[f.key] == true,
        onChanged: (b) => setState(() => vals[f.key] = b),
      );
    }
    if (f.type == 'enum' || f.type == 'enumn') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: vals[f.key]?.toString(),
          decoration: InputDecoration(
              labelText: f.label, border: const OutlineInputBorder()),
          items: f.opts!.entries
              .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (s) => setState(
              () => vals[f.key] = f.type == 'enumn' ? int.parse(s!) : s),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey('${code}_${f.key}'),
        initialValue: vals[f.key]?.toString(),
        keyboardType: f.type == 'num'
            ? const TextInputType.numberWithOptions(decimal: true)
            : f.type == 'digits'
                ? TextInputType.number
                : TextInputType.text,
        decoration: InputDecoration(
          labelText: f.label + (f.req ? '' : ' (اختیاری)'),
          border: const OutlineInputBorder(),
        ),
        onChanged: (s) {
          final t = f.type == 'text' ? s.trim() : fa2en(s).trim();
          dynamic v = t.isEmpty ? null : t;
          if (f.type == 'num' && t.isNotEmpty) {
            final n = num.tryParse(t);
            if (n != null) {
              v = (n is double && n == n.roundToDouble()) ? n.toInt() : n;
            }
          }
          setState(() => vals[f.key] = v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = cat?['code'] as String?;
    final fs = code == null ? <F>[] : fieldsFor(code, vals);
    final money = code == 'money';
    final sale = money ? 'real' : saleType;
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت آگهی')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          DropdownButtonFormField<String>(
            value: code,
            decoration: const InputDecoration(
                labelText: 'دسته', border: OutlineInputBorder()),
            items: cats
                .map((c) => DropdownMenuItem<String>(
                    value: c['code'] as String, child: Text(c['name'])))
                .toList(),
            onChanged: (s) => setState(() {
              cat = cats.firstWhere((c) => c['code'] == s);
              vals.clear();
              if (s == 'money') saleType = 'real';
            }),
          ),
          if (servers.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: serverId,
              decoration: const InputDecoration(
                  labelText: 'سرور', border: OutlineInputBorder()),
              items: servers
                  .map((s) => DropdownMenuItem<int>(
                      value: s['id'] as int, child: Text(s['name'])))
                  .toList(),
              onChanged: (v) => setState(() => serverId = v),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: title,
            decoration: const InputDecoration(
                labelText: 'عنوان', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          if (cat != null) ...[for (final f in fs) fieldWidget(f, code!)],
          if (cat != null) ...[
            if (money)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('پول بازی فقط با پول واقعی فروخته می‌شه'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'real', label: Text('پول واقعی')),
                    ButtonSegment(value: 'game', label: Text('پول بازی')),
                    ButtonSegment(value: 'both', label: Text('هر دو')),
                  ],
                  selected: {saleType},
                  onSelectionChanged: (s) => setState(() => saleType = s.first),
                ),
              ),
            if (sale != 'game')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: pReal,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'قیمت به تومان', border: OutlineInputBorder()),
                ),
              ),
            if (sale != 'real')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: pGame,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'قیمت به پول بازی',
                      border: OutlineInputBorder()),
                ),
              ),
            TextField(
              controller: desc,
              maxLines: 4,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: code == 'bug'
                    ? 'توضیحات (لینک ویدیوی باگ رو اینجا بذار)'
                    : 'توضیحات (اگه فیلم داری لینکش رو بذار)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('آیدی تماس (اختیاری)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (code == 'bug')
              const Text(
                  'برای باگ: یا لینک ویدیو توی توضیحات بذار، یا حداقل یکی از آیدی‌ها رو وارد کن',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: rub,
              decoration: const InputDecoration(
                  labelText: 'آیدی روبیکا', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tel,
              decoration: const InputDecoration(
                  labelText: 'آیدی تلگرام', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sor,
              decoration: const InputDecoration(
                  labelText: 'آیدی سروش', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            if (code != 'bug') ...[
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: imgs.length >= 5 ? null : pick,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('عکس (${imgs.length}/5)'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: imgs.isEmpty ? 0 : 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < imgs.length; i++)
                      Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(3),
                            child: Image.file(File(imgs[i].path),
                                width: 84, height: 84, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: InkWell(
                              onTap: () => setState(() => imgs.removeAt(i)),
                              child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.red,
                                  child: Icon(Icons.close,
                                      size: 14, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ] else
              const Text('برای باگ عکس یا فیلم آپلود نمی‌شه، فقط لینک.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('ثبت آگهی'),
            ),
          ],
        ],
      ),
    );
  }
}

// ====================== چت ======================
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  List<Map<String, dynamic>> cs = [];
  Map<String, String> names = {};
  bool loading = true;
  String? error;
  final me = db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await db
          .from('conversations')
          .select('id, buyer_id, seller_id, listings(title)')
          .or('buyer_id.eq.$me,seller_id.eq.$me')
          .order('created_at', ascending: false);
      cs = List<Map<String, dynamic>>.from(r);
      final ids = <String>{
        for (final c in cs) (c['buyer_id'] == me ? c['seller_id'] : c['buyer_id']) as String
      }.toList();
      if (ids.isNotEmpty) {
        final ps = await db.from('profiles').select('id, username').inFilter('id', ids);
        names = {for (final p in ps) p['id'] as String: p['username'] as String};
      }
    } catch (e) {
      error = errMsg(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('چت‌ها'), actions: [
        IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => loading = true);
              load();
            })
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : cs.isEmpty
                  ? const Center(child: Text('هنوز چتی نداری'))
                  : ListView.builder(
                      itemCount: cs.length,
                      itemBuilder: (_, i) {
                        final c = cs[i];
                        final other =
                            c['buyer_id'] == me ? c['seller_id'] : c['buyer_id'];
                        final t = (c['listings'] is Map) ? c['listings']['title'] : '';
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(names[other] ?? ''),
                          subtitle: Text(t ?? ''),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ChatPage(
                                    cid: c['id'], title: names[other] ?? 'چت')),
                          ),
                        );
                      },
                    ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String cid, title;
  const ChatPage({super.key, required this.cid, required this.title});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final c = TextEditingController();
  final me = db.auth.currentUser!.id;

  Future<void> send() async {
    final t = c.text.trim();
    if (t.isEmpty) return;
    c.clear();
    try {
      await db.from('messages').insert(
          {'conversation_id': widget.cid, 'sender_id': me, 'body': t});
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.cid)
        .order('created_at', ascending: true);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text(errMsg(snap.error!)));
                }
                final msgs = (snap.data ?? []).reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final mine = m['sender_id'] == me;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine ? Colors.teal.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(m['body'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      maxLength: 1000,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      decoration: const InputDecoration(
                          hintText: 'پیام...',
                          border: OutlineInputBorder(),
                          isDense: true),
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== پروفایل ======================
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? p;
  Map<String, dynamic>? rating;
  final phone = TextEditingController();
  bool loading = true;
  String? error;
  final me = db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      p = await db.from('profiles').select().eq('id', me).single();
      phone.text = (p!['game_phone'] ?? '') as String;
      rating = await db.from('seller_ratings').select().eq('seller_id', me).maybeSingle();
    } catch (e) {
      error = errMsg(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> savePhone() async {
    final s = fa2en(phone.text).trim();
    try {
      await db
          .from('profiles')
          .update({'game_phone': s.isEmpty ? null : s}).eq('id', me);
      if (mounted) snack(context, 'ذخیره شد');
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پروفایل')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? Center(child: Text(error ?? 'خطا'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(p!['username'] ?? '',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(rating != null
                        ? '⭐ ${rating!['avg_rating']}  (${rating!['review_count']} نظر)'
                        : 'هنوز امتیازی نداری'),
                    if (p!['is_banned'] == true)
                      const Text('اکانت شما مسدود شده',
                          style: TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'شماره تلفن بازی',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                            icon: const Icon(Icons.save), onPressed: savePhone),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.list_alt),
                      title: const Text('آگهی‌های من'),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MyListingsPage())),
                    ),
                    ListTile(
                      leading: const Icon(Icons.favorite_border),
                      title: const Text('علاقه‌مندی‌ها'),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const FavoritesPage())),
                    ),
                    if (p!['is_admin'] == true)
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings_outlined),
                        title: const Text('پنل ادمین (گزارش‌ها)'),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AdminPage())),
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('خروج'),
                      onTap: () => db.auth.signOut(),
                    ),
                  ],
                ),
    );
  }
}

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});
  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await db
          .from('listings')
          .select(listingSelect)
          .eq('user_id', db.auth.currentUser!.id)
          .order('created_at', ascending: false);
      items = List<Map<String, dynamic>>.from(r);
    } catch (e) {
      error = errMsg(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('آگهی‌های من')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : items.isEmpty
                  ? const Center(child: Text('آگهی‌ای نداری'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListingCard(
                        l: items[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DetailPage(id: items[i]['id'])),
                        ).then((_) => load()),
                      ),
                    ),
    );
  }
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});
  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await db
          .from('favorites')
          .select('listings($listingSelect)')
          .eq('user_id', db.auth.currentUser!.id);
      items = [
        for (final x in r)
          if (x['listings'] is Map) Map<String, dynamic>.from(x['listings'] as Map)
      ];
    } catch (e) {
      error = errMsg(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('علاقه‌مندی‌ها')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : items.isEmpty
                  ? const Center(child: Text('چیزی ذخیره نکردی'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListingCard(
                        l: items[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DetailPage(id: items[i]['id'])),
                        ).then((_) => load()),
                      ),
                    ),
    );
  }
}

// ====================== پنل ادمین ======================
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> rs = [];
  Map<String, String> names = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await db
          .from('reports')
          .select('*, listings(id, title)')
          .eq('resolved', false)
          .order('created_at', ascending: false);
      rs = List<Map<String, dynamic>>.from(r);
      final ids = <String>{
        for (final x in rs) ...[
          if (x['reporter_id'] != null) x['reporter_id'] as String,
          if (x['reported_user_id'] != null) x['reported_user_id'] as String,
        ]
      }.toList();
      if (ids.isNotEmpty) {
        final ps = await db.from('profiles').select('id, username').inFilter('id', ids);
        names = {for (final p in ps) p['id'] as String: p['username'] as String};
      }
    } catch (e) {
      error = errMsg(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> act(Future<void> Function() f) async {
    try {
      await f();
      await load();
    } catch (e) {
      if (mounted) snack(context, errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش‌ها')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : rs.isEmpty
                  ? const Center(child: Text('گزارش بازی نیست'))
                  : ListView.builder(
                      itemCount: rs.length,
                      itemBuilder: (_, i) {
                        final r = rs[i];
                        final lt = (r['listings'] is Map) ? r['listings']['title'] : '(حذف شده)';
                        return Card(
                          margin: const EdgeInsets.all(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('آگهی: $lt',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('گزارش‌دهنده: ${names[r['reporter_id']] ?? ''}'),
                                Text('فروشنده: ${names[r['reported_user_id']] ?? ''}'),
                                const SizedBox(height: 4),
                                Text(r['reason'] ?? ''),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    if (r['listings'] is Map)
                                      TextButton(
                                        onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => DetailPage(
                                                    id: r['listings']['id']))),
                                        child: const Text('دیدن آگهی'),
                                      ),
                                    if (r['listing_id'] != null)
                                      TextButton(
                                        onPressed: () => act(() async {
                                          await db
                                              .from('listings')
                                              .delete()
                                              .eq('id', r['listing_id']);
                                        }),
                                        child: const Text('حذف آگهی'),
                                      ),
                                    if (r['reported_user_id'] != null)
                                      TextButton(
                                        onPressed: () => act(() async {
                                          await db
                                              .from('profiles')
                                              .update({'is_banned': true}).eq(
                                                  'id', r['reported_user_id']);
                                        }),
                                        child: const Text('بن فروشنده'),
                                      ),
                                    TextButton(
                                      onPressed: () => act(() async {
                                        await db
                                            .from('reports')
                                            .update({'resolved': true}).eq('id', r['id']);
                                      }),
                                      child: const Text('بستن گزارش'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
