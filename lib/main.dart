
// lib/main.dart
// Végvári Ablak – offline MVP (2025-08-22)
// Fókusz: a megbeszélt funkciók működjenek offline: felmérés + tételek + PDF (rajzokkal),
// mentett felmérések státuszokkal + pénzügy, naptár (drag&drop), napi munka (drag & drop csapatokba),
// bevásárló lista (archív 30 nap), ügyfelek, jogosultság alapú menü, statisztika.
// Megjegyzés: egyszerű in-memory tár, app bezárásakor törlődik (MVP).

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const VegvariAblakApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// Alkalmazás és téma
// ─────────────────────────────────────────────────────────────────────────────

class VegvariAblakApp extends StatelessWidget {
  const VegvariAblakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Végvári Ablak',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFC107)),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modellek és in-memory store
// ─────────────────────────────────────────────────────────────────────────────

enum AppMenu { felmeres, arajanlatok, mentettFelmeresek, naptar, ugyfelek, bevasarloLista, napiMunka, statisztika, engedelyek }

class UserPermissions {
  final bool isAdmin;
  final bool canMoveCalendar;
  final bool canAddNapiMunka;
  final Set<AppMenu> visibleMenus;
  const UserPermissions({
    required this.isAdmin,
    required this.canMoveCalendar,
    required this.canAddNapiMunka,
    required this.visibleMenus,
  });

  factory UserPermissions.admin() => UserPermissions(
        isAdmin: true,
        canMoveCalendar: true,
        canAddNapiMunka: true,
        visibleMenus: AppMenu.values.toSet(),
      );

  factory UserPermissions.defaultUser() => UserPermissions(
        isAdmin: false,
        canMoveCalendar: false,
        canAddNapiMunka: false,
        visibleMenus: {
          AppMenu.felmeres,
          AppMenu.arajanlatok,
          AppMenu.mentettFelmeresek,
          AppMenu.naptar,
          AppMenu.ugyfelek,
          AppMenu.bevasarloLista,
          AppMenu.napiMunka,
        },
      );

  UserPermissions copyWith({
    bool? isAdmin,
    bool? canMoveCalendar,
    bool? canAddNapiMunka,
    Set<AppMenu>? visibleMenus,
  }) =>
      UserPermissions(
        isAdmin: isAdmin ?? this.isAdmin,
        canMoveCalendar: canMoveCalendar ?? this.canMoveCalendar,
        canAddNapiMunka: canAddNapiMunka ?? this.canAddNapiMunka,
        visibleMenus: visibleMenus ?? this.visibleMenus,
      );
}

class Session extends ChangeNotifier {
  static final Session I = Session._();
  Session._();

  String? userName;
  String? avatarInitials;
  UserPermissions perms = UserPermissions.defaultUser();

  bool get loggedIn => userName != null;
  void loginAs({required String name, required bool admin}) {
    userName = name;
    avatarInitials = _initials(name);
    perms = admin ? UserPermissions.admin() : UserPermissions.defaultUser();
    notifyListeners();
  }

  void logout() {
    userName = null;
    avatarInitials = null;
    perms = UserPermissions.defaultUser();
    notifyListeners();
  }

  void setVisibleMenusForUser(Set<AppMenu> menus) {
    perms = perms.copyWith(visibleMenus: menus);
    notifyListeners();
  }

  void setCalendarMove(bool v) {
    perms = perms.copyWith(canMoveCalendar: v);
    notifyListeners();
  }

  void setNapiMunkaAdd(bool v) {
    perms = perms.copyWith(canAddNapiMunka: v);
    notifyListeners();
  }

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    final take = parts.take(2).map((e) => e.isNotEmpty ? e[0] : '').join();
    return take.isEmpty ? "VA" : take.toUpperCase();
  }
}

// Ügyfelek
class Customer {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String note;
  Customer({required this.id, required this.name, required this.address, required this.phone, required this.note});
}

// Felmérés és tételek
enum ItemType {
  ablak, bejaratiAjto, belteriAjto, redony, reluxa, roletta, csuklokaros,
  szalagfuggony, plizse, ivesAluSzunyogAjto, keskenyAluFix, peremesSzunyog, magnesesSzunyog
}

extension ItemTypeX on ItemType {
  String get label => switch (this) {
        ItemType.ablak => 'Ablak',
        ItemType.bejaratiAjto => 'Bejárati ajtó',
        ItemType.belteriAjto => 'Beltéri ajtó',
        ItemType.redony => 'Redőny',
        ItemType.reluxa => 'Reluxa',
        ItemType.roletta => 'Roletta',
        ItemType.csuklokaros => 'Csuklókaros',
        ItemType.szalagfuggony => 'Szalagfüggöny',
        ItemType.plizse => 'Pliszé',
        ItemType.ivesAluSzunyogAjto => 'Íves alu szúnyogháló ajtó',
        ItemType.keskenyAluFix => 'Keskeny alu fix szúnyogháló',
        ItemType.peremesSzunyog => 'Peremes szúnyogháló',
        ItemType.magnesesSzunyog => 'Mágneses szúnyogháló',
      };
}

enum JB { J, B } // nyílás/kezelés irány
enum Layer { two, three } // 2/3 réteg
enum Panel { N, U, T } // díszpanel: Nincs/Üveges/Teli
enum WindowOpen { Ny, BNy, B } // Ny / Bukó-nyíló / Bukó

String jbToText(JB jb) => jb == JB.J ? 'Jobbos' : 'Balos';
String layerToText(Layer l) => l == Layer.two ? '2 réteg' : '3 réteg';
String panelToText(Panel p) => switch (p) { Panel.N => 'Nincs', Panel.U => 'Üveges panel', Panel.T => 'Teli panel' };
String wopenToText(WindowOpen w) => switch (w) { WindowOpen.Ny => 'Nyíló', WindowOpen.BNy => 'Bukó-nyíló', WindowOpen.B => 'Bukó' };

const kColors = ['Fehér', 'Aranytölgy', 'Antracit', 'Dió', 'Sötét tölgy', 'Mahagóni'];

class MeasurementItem {
  final String id;
  final ItemType type;
  final String name;
  final int widthMm;
  final int heightMm;
  final String color;
  final int quantity;
  final String note;
  final JB? direction; // ajtó/ablak/árnyékoló
  final WindowOpen? windowOpen; // ablak
  final Layer? layer; // ajtó+ablak
  final Panel? panel; // ajtó
  final bool motoros; // redőny típusoknál (Alu/Vakolható/Felső szekrény) – itt csak flag
  final String? motorType; // Távos/Kapcsolós/Aksis
  final Uint8List? sketchPng; // rajz
  final bool sorolt; // sorolt szerkezet kapcsoló
  final int soroltCount; // max 5

  MeasurementItem({
    required this.id,
    required this.type,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.color,
    this.quantity = 1,
    this.note = '',
    this.direction,
    this.windowOpen,
    this.layer,
    this.panel,
    this.motoros = false,
    this.motorType,
    this.sketchPng,
    this.sorolt = false,
    this.soroltCount = 1,
  });
}

class AttachedDoc {
  final String id;
  final String fileName;
  final String mime;
  final DateTime addedAt;
  final String addedBy;
  AttachedDoc({required this.id, required this.fileName, required this.mime, required this.addedAt, required this.addedBy});
}

enum SurveyStatus { draft, sent, ordered, completed, cancelled, archived }

class Survey {
  final String id;
  final String customerId;
  final String customerName;
  final String customerAddress;
  final String customerPhone;
  final String customerNote;
  final String surveyorName;
  SurveyStatus status;
  final DateTime createdAt;
  DateTime? sentAt;
  DateTime? orderedAt;
  DateTime? completedAt;
  final List<MeasurementItem> items;
  final List<AttachedDoc> docs;

  Survey({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerAddress,
    required this.customerPhone,
    required this.customerNote,
    required this.surveyorName,
    required this.status,
    required this.createdAt,
    this.sentAt,
    this.orderedAt,
    this.completedAt,
    List<MeasurementItem>? items,
    List<AttachedDoc>? docs,
  })  : items = items ?? [],
        docs = docs ?? [];
}

// Pénzügy a statisztikához
class FinanceEntry {
  final String id;
  final String surveyId;
  final DateTime date;
  final int revenue;
  final int expense;
  final String setBy;
  FinanceEntry({required this.id, required this.surveyId, required this.date, required this.revenue, required this.expense, required this.setBy});
}

// Naptár/Napi munka job
class JobItem {
  String id;
  String title; // Ügyfél – rövid
  String address;
  String desc;
  DateTime? start; // null = időpont nélküli (Napi munka gyors munka)
  String? team; // 'A' / 'B'
  JobItem({required this.id, required this.title, required this.address, required this.desc, this.start, this.team});
}

// Bevásárló lista
class ShoppingFolder {
  final String id;
  final String name;
  ShoppingFolder({required this.id, required this.name});
}

class ShoppingItem {
  final String id;
  final String folderId;
  final String name;
  final String? quantity;
  final String? note;
  final String createdBy;
  final DateTime createdAt;
  String? checkedBy;
  DateTime? checkedAt;
  bool get archived => checkedAt != null;
  ShoppingItem({
    required this.id,
    required this.folderId,
    required this.name,
    this.quantity,
    this.note,
    required this.createdBy,
    required this.createdAt,
    this.checkedBy,
    this.checkedAt,
  });
}

// AppState
class AppState extends ChangeNotifier {
  static final AppState I = AppState._();
  AppState._() {
    _purgeShoppingArchive();
  }

  final List<Customer> customers = [];
  final List<Survey> surveys = [];
  final List<JobItem> jobs = []; // naptár + napi munka
  final List<ShoppingFolder> folders = [];
  final List<ShoppingItem> shopping = [];
  final List<FinanceEntry> finance = [];

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // Ügyfél
  Customer addCustomer({required String name, required String address, required String phone, required String note}) {
    final c = Customer(id: newId(), name: name, address: address, phone: phone, note: note);
    customers.add(c);
    notifyListeners();
    return c;
  }

  // Felmérés
  Survey addDraftSurveyForCustomer(Customer c, {required String surveyor}) {
    final s = Survey(
      id: newId(),
      customerId: c.id,
      customerName: c.name,
      customerAddress: c.address,
      customerPhone: c.phone,
      customerNote: c.note,
      surveyorName: surveyor,
      status: SurveyStatus.draft,
      createdAt: DateTime.now(),
    );
    surveys.add(s);
    notifyListeners();
    return s;
  }

  void attachDocToSurvey(Survey s, AttachedDoc d) {
    s.docs.add(d);
    notifyListeners();
  }

  void addItemToSurvey(Survey s, MeasurementItem it) {
    s.items.add(it);
    notifyListeners();
  }

  void setSurveyStatus(Survey s, SurveyStatus status, {int? revenue, int? expense, required String by}) {
    s.status = status;
    final now = DateTime.now();
    if (status == SurveyStatus.sent) s.sentAt = now;
    if (status == SurveyStatus.ordered) s.orderedAt = now;
    if (status == SurveyStatus.completed) {
      s.completedAt = now;
      if (revenue != null && expense != null) {
        finance.add(FinanceEntry(id: newId(), surveyId: s.id, date: now, revenue: revenue, expense: expense, setBy: by));
      }
    }
    notifyListeners();
  }

  // Naptár/Napi munka
  void addJob(JobItem j) {
    jobs.add(j);
    notifyListeners();
  }

  void moveJob(JobItem j, {DateTime? toStart, String? toTeam}) {
    j.start = toStart ?? j.start;
    j.team = toTeam ?? j.team;
    notifyListeners();
  }

  // Bevásárló lista
  ShoppingFolder addFolder(String name) {
    final f = ShoppingFolder(id: newId(), name: name);
    folders.add(f);
    notifyListeners();
    return f;
  }

  void addShoppingItem({required String folderId, required String name, String? quantity, String? note, required String createdBy}) {
    shopping.add(ShoppingItem(
      id: newId(),
      folderId: folderId,
      name: name,
      quantity: quantity,
      note: note,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void checkShoppingItem(ShoppingItem it, String by) {
    it.checkedBy = by;
    it.checkedAt = DateTime.now();
    notifyListeners();
  }

  void uncheckShoppingItem(ShoppingItem it, String by) {
    // visszaállítás meta log
    it.checkedBy = 'Visszaállította: $by';
    it.checkedAt = null;
    notifyListeners();
  }

  void deleteShoppingItem(ShoppingItem it) {
    shopping.remove(it);
    notifyListeners();
  }

  void _purgeShoppingArchive() {
    // 30 napnál régebbi archivált tételek törlése
    final now = DateTime.now();
    shopping.removeWhere((it) => it.checkedAt != null && now.difference(it.checkedAt!).inDays >= 30);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root + Főmenü (fix sorrend, jogosultság-szűrés), jobb felső profil/bejelentkezés
// ─────────────────────────────────────────────────────────────────────────────

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Session.I, AppState.I]),
      builder: (context, _) {
        final items = _buildMenuItems(Session.I.perms);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Végvári Ablak'),
            actions: [
              IconButton(
                tooltip: Session.I.loggedIn ? 'Profil' : 'Bejelentkezés',
                onPressed: () async {
                  if (!Session.I.loggedIn) {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                    return;
                  }
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                },
                icon: Session.I.loggedIn
                    ? CircleAvatar(child: Text(Session.I.avatarInitials ?? 'P'))
                    : const Icon(Icons.person),
              ),
            ],
          ),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => items[i],
          ),
        );
      },
    );
  }

  List<Widget> _buildMenuItems(UserPermissions perms) {
    final visible = perms.visibleMenus;
    final List<_MenuEntry> all = [
      _MenuEntry(AppMenu.felmeres, Icons.assignment, 'Felmérés', 'Új/Leendő felmérések, tételek, PDF'),
      _MenuEntry(AppMenu.arajanlatok, Icons.receipt_long, 'Árajánlatok', 'Kész ajánlatok, export'),
      _MenuEntry(AppMenu.mentettFelmeresek, Icons.save, 'Mentett felmérések', 'Státuszok + dokumentumok'),
      _MenuEntry(AppMenu.naptar, Icons.calendar_month, 'Naptár', 'Heti, 30 perc, drag&drop (csak jogosultak)'),
      _MenuEntry(AppMenu.ugyfelek, Icons.contacts, 'Ügyfelek', 'Kereshető lista'),
      _MenuEntry(AppMenu.bevasarloLista, Icons.shopping_cart, 'Bevásárló lista', 'Mappák + tételek, archív'),
      _MenuEntry(AppMenu.napiMunka, Icons.view_day, 'Napi munka', 'Ma betáblázott munkák + Csapat A/B'),
      _MenuEntry(AppMenu.statisztika, Icons.bar_chart, 'Statisztika', 'Bevétel/Kiadás időszakokra'),
      if (perms.isAdmin) _MenuEntry(AppMenu.engedelyek, Icons.admin_panel_settings, 'Engedélyek', 'Menü láthatóság és jogok'),
    ];

    return all
        .where((e) => visible.contains(e.key) || (e.key == AppMenu.engedelyek && perms.isAdmin))
        .map((e) => Card(
              child: ListTile(
                leading: Icon(e.icon),
                title: Text(e.title),
                subtitle: Text(e.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openMenu(e.key),
              ),
            ))
        .toList();
  }

  void _openMenu(AppMenu key) {
    switch (key) {
      case AppMenu.felmeres:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FelmeresHome()));
        break;
      case AppMenu.arajanlatok:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ArajanlatokScreen()));
        break;
      case AppMenu.mentettFelmeresek:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MentettFelmeresekScreen()));
        break;
      case AppMenu.naptar:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const NaptarScreen()));
        break;
      case AppMenu.ugyfelek:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UgyfelekScreen()));
        break;
      case AppMenu.bevasarloLista:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BevasarloListaScreen()));
        break;
      case AppMenu.napiMunka:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const NapiMunkaScreen()));
        break;
      case AppMenu.statisztika:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const StatisztikaScreen()));
        break;
      case AppMenu.engedelyek:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const EngedelyekScreen()));
        break;
    }
  }
}

class _MenuEntry {
  final AppMenu key; final IconData icon; final String title; final String subtitle;
  _MenuEntry(this.key, this.icon, this.title, this.subtitle);
}

// ─────────────────────────────────────────────────────────────────────────────
// Felmérés modul
// ─────────────────────────────────────────────────────────────────────────────

class FelmeresHome extends StatefulWidget {
  const FelmeresHome({super.key});
  @override
  State<FelmeresHome> createState() => _FelmeresHomeState();
}

class _FelmeresHomeState extends State<FelmeresHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Felmérés')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Új leendő felmérés rögzítése'),
              subtitle: const Text('Ügyfél adatai → piszkozat (később kitölthető)'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSurveyDraftScreen())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Felmérések listája'),
              subtitle: const Text('Leendő / Betáblázva / Kitöltve / Lemondva / Archív'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SurveysListScreen())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF export (felmérési lap)'),
              subtitle: const Text('Rajzokkal – a felmérés részletein belül is elérhető'),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nyisd meg egy felmérés részleteit PDF-hez.'))),
            ),
          ),
        ],
      ),
    );
  }
}

class NewSurveyDraftScreen extends StatefulWidget {
  const NewSurveyDraftScreen({super.key});
  @override
  State<NewSurveyDraftScreen> createState() => _NewSurveyDraftScreenState();
}

class _NewSurveyDraftScreenState extends State<NewSurveyDraftScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _surveyor = TextEditingController();

  @override
  void dispose() {
    _name.dispose(); _address.dispose(); _phone.dispose(); _note.dispose(); _surveyor.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final c = AppState.I.addCustomer(name: _name.text.trim(), address: _address.text.trim(), phone: _phone.text.trim(), note: _note.text.trim());
    final s = AppState.I.addDraftSurveyForCustomer(c, surveyor: _surveyor.text.trim());
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SurveyDetailScreen(survey: s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Új leendő felmérés')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Ügyfél neve *', prefixIcon: Icon(Icons.person)), validator: _req),
            const SizedBox(height: 12),
            TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Cím *', prefixIcon: Icon(Icons.location_on)), validator: _req),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Telefon'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextFormField(controller: _surveyor, decoration: const InputDecoration(labelText: 'Felmérő neve'),),
            const SizedBox(height: 12),
            TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Megjegyzés'), maxLines: 3),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Mentés és megnyitás')),
          ],
        ),
      ),
    );
  }

  String? _req(String? v) => (v==null || v.trim().isEmpty) ? 'Kötelező' : null;
}

class SurveysListScreen extends StatefulWidget {
  const SurveysListScreen({super.key});
  @override
  State<SurveysListScreen> createState() => _SurveysListScreenState();
}

class _SurveysListScreenState extends State<SurveysListScreen> {
  SurveyStatus? filter;
  String q = '';

  @override
  Widget build(BuildContext context) {
    final src = AppState.I.surveys;
    final items = src.where((s){
      if (filter != null && s.status != filter) return false;
      if (q.isNotEmpty) {
        final hay = '${s.customerName} ${s.customerAddress} ${s.surveyorName}'.toLowerCase();
        if (!hay.contains(q.toLowerCase())) return false;
      }
      return true;
    }).toList()
      ..sort((a,b)=> b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Felmérések listája')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Keresés név/cím szerint'), onChanged: (v)=>setState(()=>q=v))),
              const SizedBox(width: 8),
              DropdownButton<SurveyStatus?>(
                value: filter,
                items: [null, ...SurveyStatus.values].map((f)=>DropdownMenuItem(value:f, child: Text(f?.name ?? 'Mind'))).toList(),
                onChanged: (v)=>setState(()=>filter=v),
              )
            ]),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __)=>const SizedBox(height: 8),
              itemBuilder: (_, i){
                final s = items[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text('${s.customerName} – ${s.customerAddress}'),
                    subtitle: Text('Státusz: ${s.status.name}  •  ${s.createdAt.toLocal()}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_)=> SurveyDetailScreen(survey: s))),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class SurveyDetailScreen extends StatefulWidget {
  final Survey survey;
  const SurveyDetailScreen({super.key, required this.survey});
  @override
  State<SurveyDetailScreen> createState() => _SurveyDetailScreenState();
}

class _SurveyDetailScreenState extends State<SurveyDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.survey;
    return Scaffold(
      appBar: AppBar(title: const Text('Felmérés részletek'), actions: [
        IconButton(icon: const Icon(Icons.picture_as_pdf), tooltip: 'Felmérési lap PDF', onPressed: _exportPdf),
        IconButton(icon: const Icon(Icons.attach_file), tooltip: 'Dokumentum csatolása', onPressed: _attachDoc),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_)=> AddItemScreen(survey: s))),
        icon: const Icon(Icons.add),
        label: const Text('Tétel hozzáadása'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(s.customerName),
              subtitle: Text('${s.customerAddress}\nTel: ${s.customerPhone.isEmpty?'-':s.customerPhone}\nMegjegyzés: ${s.customerNote.isEmpty?'-':s.customerNote}'),
            ),
          ),
          const SizedBox(height: 8),
          _StatusBar(s: s, onChange: _onStatusChange),
          const SizedBox(height: 8),
          Text('Tételek', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...s.items.map((it)=> Card(
            child: ExpansionTile(
              leading: const Icon(Icons.straighten),
              title: Text('${it.type.label} – ${it.name}'),
              subtitle: Text('Méret: ${it.widthMm}×${it.heightMm}   Szín: ${it.color}   Darab: ${it.quantity}'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (it.direction!=null) Text('Irány: ${jbToText(it.direction!)}'),
                      if (it.windowOpen!=null) Text('Nyitásmód: ${wopenToText(it.windowOpen!)}'),
                      if (it.layer!=null) Text('Réteg: ${layerToText(it.layer!)}'),
                      if (it.panel!=null) Text('Díszpanel: ${panelToText(it.panel!)}'),
                      if (it.motoros) Text('Motoros: ${it.motorType ?? 'igen'}'),
                      if (it.sorolt) Text('Sorolt szerkezet: ${it.soroltCount} elem'),
                      const SizedBox(height: 8),
                      Text('Megjegyzés: ${it.note.isEmpty?'-':it.note}'),
                      const SizedBox(height: 8),
                      if (it.sketchPng!=null) Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Vázlat:'),
                          const SizedBox(height: 6),
                          Image.memory(it.sketchPng!, height: 160, fit: BoxFit.contain),
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          )),
          const SizedBox(height: 12),
          Text('Csatolt dokumentumok', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (s.docs.isEmpty) const Text('Nincs csatolt dokumentum'),
          ...s.docs.map((d)=> ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(d.fileName),
            subtitle: Text('Feltöltve: ${d.addedAt.toLocal()} • ${d.addedBy}'),
          )),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _onStatusChange(SurveyStatus st) async {
    final s = widget.survey;
    if (st == SurveyStatus.completed) {
      final res = await showDialog<(int,int)?>(context: context, builder: (_)=> const _RevenueExpenseDialog());
      if (res == null) return;
      AppState.I.setSurveyStatus(s, status: st, revenue: res.$1, expense: res.$2, by: Session.I.userName ?? 'Ismeretlen');
    } else {
      AppState.I.setSurveyStatus(s, status: st, by: Session.I.userName ?? 'Ismeretlen');
    }
  }

  Future<void> _attachDoc() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png']);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final doc = AttachedDoc(id: AppState.I.newId(), fileName: f.name, mime: f.extension ?? 'file', addedAt: DateTime.now(), addedBy: Session.I.userName ?? 'Ismeretlen');
    AppState.I.attachDocToSurvey(widget.survey, doc);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Csatolva: ${f.name}')));
  }

  Future<void> _exportPdf() async {
    final s = widget.survey;
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Header(level: 0, child: pw.Text('Felmérési lap – Végvári Ablak')),
        pw.Text('Ügyfél: ${s.customerName}'),
        pw.Text('Cím: ${s.customerAddress}'),
        pw.Text('Telefon: ${s.customerPhone}'),
        pw.Text('Megjegyzés: ${s.customerNote}'),
        pw.SizedBox(height: 10),
        pw.Text('Felmérő: ${s.surveyorName} • Dátum: ${s.createdAt.toLocal()}'),
        pw.SizedBox(height: 12),
        ...s.items.map((it) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Divider(),
            pw.Text('${it.type.label} – ${it.name}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('Méret: ${it.widthMm} × ${it.heightMm} mm    Darab: ${it.quantity}    Szín: ${it.color}'),
            if (it.direction!=null) pw.Text('Irány: ${jbToText(it.direction!)}'),
            if (it.windowOpen!=null) pw.Text('Nyitásmód: ${wopenToText(it.windowOpen!)}'),
            if (it.layer!=null) pw.Text('Réteg: ${layerToText(it.layer!)}'),
            if (it.panel!=null) pw.Text('Díszpanel: ${panelToText(it.panel!)}'),
            if (it.motoros) pw.Text('Motoros: ${it.motorType ?? 'igen'}'),
            if (it.sorolt) pw.Text('Sorolt szerkezet: ${it.soroltCount} elem'),
            pw.Text('Megjegyzés: ${it.note.isEmpty?'-':it.note}'),
            if (it.sketchPng!=null) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Image(pw.MemoryImage(it.sketchPng!), height: 160)),
          ],
        )),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }
}

class _StatusBar extends StatelessWidget {
  final Survey s;
  final void Function(SurveyStatus) onChange;
  const _StatusBar({required this.s, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final options = [
      (SurveyStatus.draft, 'Leendő'),
      (SurveyStatus.sent, 'Elküldve'),
      (SurveyStatus.ordered, 'Megrendelve'),
      (SurveyStatus.completed, 'Elkészült'),
      (SurveyStatus.cancelled, 'Lemondva'),
      (SurveyStatus.archived, 'Archív'),
    ];
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: options.map((opt){
        final active = s.status == opt.$1;
        return ChoiceChip(
          selected: active,
          label: Text(opt.$2),
          onSelected: (_) => onChange(opt.$1),
        );
      }).toList(),
    );
  }
}

class _RevenueExpenseDialog extends StatefulWidget {
  const _RevenueExpenseDialog();
  @override
  State<_RevenueExpenseDialog> createState() => _RevenueExpenseDialogState();
}

class _RevenueExpenseDialogState extends State<_RevenueExpenseDialog> {
  final _rev = TextEditingController(); final _exp = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pénzügy rögzítése'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _rev, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bevétel (Ft)')),
          const SizedBox(height: 8),
          TextField(controller: _exp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kiadás (Ft)')),
        ],
      ),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Mégse')),
        FilledButton(onPressed: (){
          final r = int.tryParse(_rev.text.trim()) ?? 0;
          final e = int.tryParse(_exp.text.trim()) ?? 0;
          Navigator.pop(context, (r,e));
        }, child: const Text('Mentés')),
      ],
    );
  }
}

// Tétel hozzáadása – dinamikus űrlap rövid jelölésekkel
class AddItemScreen extends StatefulWidget {
  final Survey survey;
  const AddItemScreen({super.key, required this.survey});
  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _form = GlobalKey<FormState>();
  ItemType type = ItemType.ablak;
  final _name = TextEditingController();
  final _w = TextEditingController();
  final _h = TextEditingController();
  String color = kColors.first;
  final _qty = TextEditingController(text: '1');
  String note = '';
  JB? dir;
  WindowOpen? wopen;
  Layer? layer;
  Panel? panel;
  bool motoros = false;
  String? motorType;
  bool sorolt = false;
  int soroltCount = 1;

  final _sig = SignatureController(penStrokeWidth: 3, penColor: Colors.black);

  @override
  void dispose() {
    _name.dispose(); _w.dispose(); _h.dispose(); _qty.dispose(); _sig.dispose();
    super.dispose();
  }

  bool get isDoor => type == ItemType.bejaratiAjto || type == ItemType.belteriAjto;
  bool get isWindow => type == ItemType.ablak;
  bool get isShade => {ItemType.redony, ItemType.reluxa, ItemType.roletta, ItemType.csuklokaros, ItemType.szalagfuggony, ItemType.plizse}.contains(type)
      || {ItemType.ivesAluSzunyogAjto, ItemType.keskenyAluFix, ItemType.peremesSzunyog, ItemType.magnesesSzunyog}.contains(type);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tétel hozzáadása')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // típus választó
            _Dropdown<ItemType>(
              label: 'Típus',
              value: type,
              items: ItemType.values.map((e) => DropdownMenuItem(value: e, child: Text(e.label))).toList(),
              onChanged: (v) => setState(()=> type = v ?? type),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Megnevezés *'), validator: _req),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _w, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Szélesség (mm) *'), validator: _req)),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Magasság (mm) *'), validator: _req)),
            ]),
            const SizedBox(height: 12),
            _Dropdown<String>(label: 'Szín', value: color, items: kColors.map((c)=>DropdownMenuItem(value:c, child: Text(c))).toList(), onChanged: (v)=> setState(()=> color = v ?? color)),
            const SizedBox(height: 12),
            if (isDoor || isWindow || isShade) _JBSelector(value: dir, onChanged: (v)=> setState(()=> dir = v)), // J/B mindenütt ahol értelmezett
            if (isWindow) ...[
              const SizedBox(height: 12),
              _WindowOpenSelector(value: wopen, onChanged: (v)=> setState(()=> wopen = v)),
            ],
            if (isDoor || isWindow) ...[
              const SizedBox(height: 12),
              _LayerSelector(value: layer, onChanged: (v)=> setState(()=> layer = v)),
            ],
            if (isDoor) ...[
              const SizedBox(height: 12),
              _PanelSelector(value: panel, onChanged: (v)=> setState(()=> panel = v)),
            ],
            if (type == ItemType.redony) ...[
              const SizedBox(height: 12),
              CheckboxListTile(value: motoros, onChanged: (v)=> setState(()=> motoros = v ?? false), title: const Text('Motoros?')),
              if (motoros) _Dropdown<String>(
                label: 'Motor típusa',
                value: motorType,
                items: ['Távirányítós','Kapcsolós','Akkumulátoros'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(),
                onChanged: (v)=> setState(()=> motorType = v),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Darabszám'),)),
              const SizedBox(width: 12),
              Expanded(child: SwitchListTile(value: sorolt, onChanged: (v)=> setState(()=> sorolt = v), title: const Text('Sorolt szerkezet'))),
            ]),
            if (sorolt) Row(children: [
              const Text('Elemszám:'), const SizedBox(width: 8),
              DropdownButton<int>(value: soroltCount, items: [1,2,3,4,5].map((e)=>DropdownMenuItem(value:e, child: Text('$e'))).toList(), onChanged: (v)=> setState(()=> soroltCount = v ?? 1)),
            ]),
            const SizedBox(height: 12),
            Text('Megjegyzés'),
            const SizedBox(height: 6),
            _MultilineNote(onSaved: (v)=> note = v ?? ''),
            const SizedBox(height: 12),
            Text('Vázlat (rajz)'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
              height: 180,
              child: Signature(controller: _sig, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(onPressed: ()=> _sig.clear(), icon: const Icon(Icons.clear), label: const Text('Törlés')),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Tétel mentése')),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String? _req(String? v) => (v==null || v.trim().isEmpty) ? 'Kötelező' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    Uint8List? png;
    if (_sig.isNotEmpty) {
      png = await _sig.toPngBytes();
    }
    final item = MeasurementItem(
      id: AppState.I.newId(),
      type: type,
      name: _name.text.trim(),
      widthMm: int.tryParse(_w.text.trim()) ?? 0,
      heightMm: int.tryParse(_h.text.trim()) ?? 0,
      color: color,
      quantity: int.tryParse(_qty.text.trim()) ?? 1,
      note: note,
      direction: dir,
      windowOpen: wopen,
      layer: layer,
      panel: panel,
      motoros: motoros,
      motorType: motorType,
      sketchPng: png,
      sorolt: sorolt,
      soroltCount: soroltCount,
    );
    AppState.I.addItemToSurvey(widget.survey, item);
    if (mounted) Navigator.pop(context);
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label; final T? value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(child: DropdownButton<T>(value: value, isExpanded: true, items: items, onChanged: onChanged)),
    );
  }
}

class _JBSelector extends StatelessWidget {
  final JB? value; final ValueChanged<JB> onChanged;
  const _JBSelector({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: ChoiceChip(selected: value==JB.J, label: const Text('J'), onSelected: (_)=> onChanged(JB.J))),
      const SizedBox(width: 8),
      Expanded(child: ChoiceChip(selected: value==JB.B, label: const Text('B'), onSelected: (_)=> onChanged(JB.B))),
    ]);
  }
}

class _LayerSelector extends StatelessWidget {
  final Layer? value; final ValueChanged<Layer> onChanged;
  const _LayerSelector({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: ChoiceChip(selected: value==Layer.two, label: const Text('2'), onSelected: (_)=> onChanged(Layer.two))),
      const SizedBox(width: 8),
      Expanded(child: ChoiceChip(selected: value==Layer.three, label: const Text('3'), onSelected: (_)=> onChanged(Layer.three))),
    ]);
  }
}

class _PanelSelector extends StatelessWidget {
  final Panel? value; final ValueChanged<Panel> onChanged;
  const _PanelSelector({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: ChoiceChip(selected: value==Panel.N, label: const Text('N'), onSelected: (_)=> onChanged(Panel.N))),
      const SizedBox(width: 8),
      Expanded(child: ChoiceChip(selected: value==Panel.U, label: const Text('Ü'), onSelected: (_)=> onChanged(Panel.U))),
      const SizedBox(width: 8),
      Expanded(child: ChoiceChip(selected: value==Panel.T, label: const Text('T'), onSelected: (_)=> onChanged(Panel.T))),
    ]);
  }
}

class _WindowOpenSelector extends StatelessWidget {
  final WindowOpen? value; final ValueChanged<WindowOpen> onChanged;
  const _WindowOpenSelector({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, children: [
      ChoiceChip(selected: value==WindowOpen.Ny, label: const Text('Ny'), onSelected: (_)=> onChanged(WindowOpen.Ny)),
      ChoiceChip(selected: value==WindowOpen.BNy, label: const Text('B-Ny'), onSelected: (_)=> onChanged(WindowOpen.BNy)),
      ChoiceChip(selected: value==WindowOpen.B, label: const Text('B'), onSelected: (_)=> onChanged(WindowOpen.B)),
    ]);
  }
}

class _MultilineNote extends StatefulWidget {
  final FormFieldSetter<String>? onSaved;
  const _MultilineNote({this.onSaved});
  @override
  State<_MultilineNote> createState() => _MultilineNoteState();
}

class _MultilineNoteState extends State<_MultilineNote> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return TextFormField(controller: _ctrl, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Részletes megjegyzés…'), onSaved: widget.onSaved);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mentett felmérések – státuszok + dokumentumok csatolása
// ─────────────────────────────────────────────────────────────────────────────

class MentettFelmeresekScreen extends StatelessWidget {
  const MentettFelmeresekScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = AppState.I.surveys.where((s)=> s.status!=SurveyStatus.draft).toList()
      ..sort((a,b)=> (b.sentAt ?? b.createdAt).compareTo(a.sentAt ?? a.createdAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Mentett felmérések')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __)=> const SizedBox(height: 8),
        itemBuilder: (_, i){
          final s = items[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text(s.customerName),
              subtitle: Text('Státusz: ${s.status.name}  •  Tételek: ${s.items.length}  •  Dok: ${s.docs.length}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: ()=> Navigator.push(_, MaterialPageRoute(builder: (__)=> SurveyDetailScreen(survey: s))),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Árajánlatok – placeholder (a PDF export külön készül az ajánlatokhoz később)
// ─────────────────────────────────────────────────────────────────────────────

class ArajanlatokScreen extends StatelessWidget {
  const ArajanlatokScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Árajánlatok')), body: const Center(child: Text('Kész ajánlatok listája – később')));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ügyfelek
// ─────────────────────────────────────────────────────────────────────────────

class UgyfelekScreen extends StatefulWidget {
  const UgyfelekScreen({super.key});
  @override
  State<UgyfelekScreen> createState() => _UgyfelekScreenState();
}

class _UgyfelekScreenState extends State<UgyfelekScreen> {
  String q='';
  @override
  Widget build(BuildContext context) {
    final items = AppState.I.customers.where((c)=> c.name.toLowerCase().contains(q.toLowerCase()) || c.address.toLowerCase().contains(q.toLowerCase())).toList()
      ..sort((a,b)=> a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Ügyfelek')),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Keresés név/cím'), onChanged: (v)=> setState(()=> q=v))),
          Expanded(child: ListView.separated(
            itemCount: items.length, separatorBuilder: (_, __)=> const Divider(height:1),
            itemBuilder: (_, i){
              final c = items[i];
              return ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(c.name), subtitle: Text(c.address), trailing: Text(c.phone));
            },
          ))
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Naptár – heti, 30 perces slotok, drag&drop csak jogosultaknak
// ─────────────────────────────────────────────────────────────────────────────

class NaptarScreen extends StatefulWidget {
  const NaptarScreen({super.key});
  @override
  State<NaptarScreen> createState() => _NaptarScreenState();
}

class _NaptarScreenState extends State<NaptarScreen> {
  DateTime weekStart = _mondayOf(DateTime.now());
  static DateTime _mondayOf(DateTime d){ final wd=d.weekday; return DateTime(d.year,d.month,d.day).subtract(Duration(days: wd-1)); }
  static String _wd(int w){ const n=['H','K','Sze','Cs','P','Szo','V']; return n[w-1]; }
  static String _fmt(TimeOfDay t)=> '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final startHour=8, endHour=18; final slotsPerDay=(endHour-startHour)*2;
    final days = List.generate(7, (i)=> weekStart.add(Duration(days:i)));
    final slots = List.generate(slotsPerDay, (i)=> TimeOfDay(hour: startHour + (i~/2), minute: (i%2)*30));

    return Scaffold(
      appBar: AppBar(title: const Text('Naptár'), actions: [
        IconButton(onPressed: ()=> setState(()=> weekStart=weekStart.subtract(const Duration(days:7))), icon: const Icon(Icons.chevron_left)),
        IconButton(onPressed: ()=> setState(()=> weekStart=_mondayOf(DateTime.now())), icon: const Icon(Icons.today)),
        IconButton(onPressed: ()=> setState(()=> weekStart=weekStart.add(const Duration(days:7))), icon: const Icon(Icons.chevron_right)),
      ]),
      body: Column(
        children: [
          Row(children: [
            const SizedBox(width:70),
            for (final d in days) Expanded(child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))), child: Text('${_wd(d.weekday)}\n${d.month}.${d.day.toString().padLeft(2,'0')}', textAlign: TextAlign.center))),
          ]),
          const Divider(height:1),
          Expanded(child: SingleChildScrollView(
            child: Column(children: [
              for (int r=0;r<slotsPerDay;r++)
                SizedBox(height:56, child: Row(children: [
                  Container(width:70, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right:8), child: Text(_fmt(slots[r]), style: const TextStyle(color: Colors.black54))),
                  for (int c=0;c<7;c++)
                    Expanded(child: _CalendarCell(day: days[c], tod: slots[r])),
                ])),
            ]),
          )),
        ],
      ),
      floatingActionButton: Session.I.perms.canMoveCalendar ? FloatingActionButton.extended(
        onPressed: (){
          final start = DateTime(weekStart.year, weekStart.month, weekStart.day, 9, 0);
          AppState.I.addJob(JobItem(id: AppState.I.newId(), title: 'Új munka', address: '-', desc: '-', start: start));
        }, icon: const Icon(Icons.add), label: const Text('Új munka'),
      ) : null,
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final DateTime day; final TimeOfDay tod;
  const _CalendarCell({required this.day, required this.tod});

  @override
  Widget build(BuildContext context) {
    final slotStart = DateTime(day.year, day.month, day.day, tod.hour, tod.minute);
    final jobsHere = AppState.I.jobs.where((j)=> j.start == slotStart).toList();

    Widget content = Stack(children: [
      for (final job in jobsHere)
        Positioned.fill(child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Session.I.perms.canMoveCalendar
              ? LongPressDraggable<JobItem>(
                  data: job,
                  feedback: Material(elevation: 4, child: Container(padding: const EdgeInsets.all(8), color: Colors.amber, child: Text(job.title))),
                  child: _JobChip(job: job),
                )
              : _JobChip(job: job),
        ))
    ]);

    return DragTarget<JobItem>(
      onWillAccept: (_) => Session.I.perms.canMoveCalendar,
      onAccept: (job){
        if (!Session.I.perms.canMoveCalendar) return;
        AppState.I.moveJob(job, toStart: slotStart);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Áthelyezve')));
      },
      builder: (context, cand, rej)=> Container(
        margin: const EdgeInsets.all(1), decoration: BoxDecoration(border: Border.all(color: Colors.black12), color: cand.isNotEmpty ? Colors.amber.withOpacity(0.2): null),
        child: content,
      ),
    );
  }
}

class _JobChip extends StatelessWidget {
  final JobItem job;
  const _JobChip({required this.job});
  @override
  Widget build(BuildContext context) {
    final t = job.start!=null ? TimeOfDay(hour: job.start!.hour, minute: job.start!.minute) : null;
    return Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.amber.shade200), padding: const EdgeInsets.all(6), child: Row(children: [
      const Icon(Icons.work, size: 16), const SizedBox(width: 6),
      Expanded(child: Text(job.title, overflow: TextOverflow.ellipsis)),
      if (t!=null) Text('${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}'),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Napi munka – drag&drop, mint mappába húzás
// ─────────────────────────────────────────────────────────────────────────────

class NapiMunkaScreen extends StatefulWidget {
  const NapiMunkaScreen({super.key});
  @override
  State<NapiMunkaScreen> createState() => _NapiMunkaScreenState();
}

class _NapiMunkaScreenState extends State<NapiMunkaScreen> {
  DateTime day = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final jobsToday = AppState.I.jobs.where((j)=> j.start!=null && _sameDay(j.start!, day)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Napi munka'), actions: [
        IconButton(onPressed: ()=> setState(()=> day = day.subtract(const Duration(days:1))), icon: const Icon(Icons.chevron_left)),
        IconButton(onPressed: ()=> setState(()=> day = DateTime.now()), icon: const Icon(Icons.today)),
        IconButton(onPressed: ()=> setState(()=> day = day.add(const Duration(days:1))), icon: const Icon(Icons.chevron_right)),
      ]),
      floatingActionButton: Session.I.perms.canAddNapiMunka ? FloatingActionButton.extended(
        onPressed: _addQuick, icon: const Icon(Icons.add), label: const Text('Hozzáadás'),
      ) : null,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ma betáblázott munkák', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: jobsToday.length,
                separatorBuilder: (_, __)=> const SizedBox(width: 8),
                itemBuilder: (_, i){
                  final j = jobsToday[i];
                  final card = _JobCard(job: j);
                  return Session.I.perms.canMoveCalendar
                    ? LongPressDraggable<JobItem>(data: j, feedback: _dragGhost(j), child: card)
                    : card;
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _TeamBucket(label: 'Csapat A', team: 'A')),
              const SizedBox(width: 12),
              Expanded(child: _TeamBucket(label: 'Csapat B', team: 'B')),
            ]),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year==b.year && a.month==b.month && a.day==b.day;

  void _addQuick() {
    final name = TextEditingController(); final addr = TextEditingController(); final d = TextEditingController();
    showDialog(context: context, builder: (_)=> AlertDialog(
      title: const Text('Gyors munka hozzáadása'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Ügyfél')),
        TextField(controller: addr, decoration: const InputDecoration(labelText: 'Cím')),
        TextField(controller: d, decoration: const InputDecoration(labelText: 'Rövid leírás')),
      ]),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Mégse')),
        FilledButton(onPressed: (){
          AppState.I.addJob(JobItem(id: AppState.I.newId(), title: name.text.trim().isEmpty?'Munka':name.text.trim(), address: addr.text.trim(), desc: d.text.trim(), start: null));
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hozzáadva a listához')));
        }, child: const Text('Mentés'))
      ],
    ));
  }

  Widget _dragGhost(JobItem j) => Material(elevation: 6, child: Container(padding: const EdgeInsets.all(8), color: Colors.amber, child: Text(j.title)));
}

class _JobCard extends StatelessWidget {
  final JobItem job;
  const _JobCard({required this.job});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(job.title, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(job.address, maxLines: 1, overflow: TextOverflow.ellipsis),
        const Spacer(),
        Text(job.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
      ]),
    );
  }
}

class _TeamBucket extends StatelessWidget {
  final String label; final String team;
  const _TeamBucket({required this.label, required this.team});

  @override
  Widget build(BuildContext context) {
    final items = AppState.I.jobs.where((j)=> j.team == team).toList();
    return DragTarget<JobItem>(
      onWillAccept: (_) => Session.I.perms.canMoveCalendar,
      onAccept: (job){
        if (!Session.I.perms.canMoveCalendar) return;
        AppState.I.moveJob(job, toTeam: team);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Áthelyezve ide: $label')));
      },
      builder: (context, cand, rej)=> Container(
        height: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(12),
          color: cand.isNotEmpty ? Colors.amber.withOpacity(0.2) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.folder_open), const SizedBox(width:8), Text(label, style: Theme.of(context).textTheme.titleMedium)]),
          const SizedBox(height: 8),
          Expanded(child: items.isEmpty ? const Center(child: Text('Húzd ide a munkát')) : ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __)=> const SizedBox(height: 8),
            itemBuilder: (_, i)=> _JobChip(job: items[i]),
          )),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bevásárló lista – mappák (csak név), tételek, archív 30 nap, visszaállítás/törlés
// ─────────────────────────────────────────────────────────────────────────────

class BevasarloListaScreen extends StatefulWidget {
  const BevasarloListaScreen({super.key});
  @override
  State<BevasarloListaScreen> createState() => _BevasarloListaScreenState();
}

class _BevasarloListaScreenState extends State<BevasarloListaScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bevásárló lista')),
      floatingActionButton: FloatingActionButton(onPressed: _addFolder, child: const Icon(Icons.create_new_folder)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __)=> const SizedBox(height: 8),
        itemCount: AppState.I.folders.length,
        itemBuilder: (_, i){
          final f = AppState.I.folders[i];
          return Card(child: ListTile(
            leading: const Icon(Icons.folder),
            title: Text(f.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: ()=> Navigator.push(_, MaterialPageRoute(builder: (__)=> ShoppingFolderScreen(folder: f))),
          ));
        },
      ),
    );
  }

  void _addFolder() {
    final name = TextEditingController();
    showDialog(context: context, builder: (_)=> AlertDialog(
      title: const Text('Új mappa'),
      content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Mappa neve')),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Mégse')),
        FilledButton(onPressed: (){ AppState.I.addFolder(name.text.trim().isEmpty?'Mappa':name.text.trim()); Navigator.pop(context); }, child: const Text('Létrehozás')),
      ],
    ));
  }
}

class ShoppingFolderScreen extends StatefulWidget {
  final ShoppingFolder folder;
  const ShoppingFolderScreen({super.key, required this.folder});
  @override
  State<ShoppingFolderScreen> createState() => _ShoppingFolderScreenState();
}

class _ShoppingFolderScreenState extends State<ShoppingFolderScreen> {
  bool showArchive = false;
  @override
  Widget build(BuildContext context) {
    final items = AppState.I.shopping.where((it)=> it.folderId==widget.folder.id && (showArchive ? it.archived : !it.archived)).toList()
      ..sort((a,b)=> (a.archived?1:0).compareTo(b.archived?1:0));
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.name), actions: [
        IconButton(onPressed: ()=> setState(()=> showArchive = !showArchive), icon: Icon(showArchive?Icons.unarchive:Icons.archive)),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _addItem, child: const Icon(Icons.add)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __)=> const SizedBox(height: 8),
        itemCount: items.length,
        itemBuilder: (_, i){
          final it = items[i];
          return Card(
            child: ListTile(
              leading: Checkbox(value: it.archived, onChanged: (v){
                if (v==true) {
                  AppState.I.checkShoppingItem(it, Session.I.userName ?? 'Ismeretlen');
                } else {
                  AppState.I.uncheckShoppingItem(it, Session.I.userName ?? 'Ismeretlen');
                }
              }),
              title: Text(it.name, style: TextStyle(decoration: it.archived? TextDecoration.lineThrough: TextDecoration.none)),
              subtitle: Text([if(it.quantity!=null && it.quantity!.isNotEmpty) it.quantity!, if(it.note!=null && it.note!.isNotEmpty) 'Megj: ${it.note}', if(it.archived && it.checkedBy!=null) 'Kipipálta: ${it.checkedBy}'].join('  •  ')),
              trailing: it.archived ? IconButton(icon: const Icon(Icons.delete_forever), onPressed: ()=> AppState.I.deleteShoppingItem(it)) : null,
              onTap: (){
                showDialog(context: context, builder: (_)=> AlertDialog(
                  title: Text(it.name),
                  content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (it.quantity!=null && it.quantity!.isNotEmpty) Text('Mennyiség: ${it.quantity}'),
                    if (it.note!=null && it.note!.isNotEmpty) Text('Megjegyzés: ${it.note}'),
                    Text('Hozzáadta: ${it.createdBy} • ${it.createdAt.toLocal()}'),
                    if (it.checkedBy!=null && it.archived) Text('Kipipálta: ${it.checkedBy} • ${it.checkedAt}'),
                  ]),
                  actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('OK'))],
                ));
              },
            ),
          );
        },
      ),
    );
  }

  void _addItem() {
    final name = TextEditingController(); final qty = TextEditingController(); final note = TextEditingController();
    showDialog(context: context, builder: (_)=> AlertDialog(
      title: const Text('Új tétel'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Megnevezés *')),
        TextField(controller: qty, decoration: const InputDecoration(labelText: 'Mennyiség/egység')), 
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Megjegyzés'), maxLines: 3),
      ]),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Mégse')),
        FilledButton(onPressed: (){
          AppState.I.addShoppingItem(folderId: widget.folder.id, name: name.text.trim().isEmpty?'Tétel':name.text.trim(), quantity: qty.text.trim(), note: note.text.trim(), createdBy: Session.I.userName ?? 'Ismeretlen');
          Navigator.pop(context);
        }, child: const Text('Hozzáadás')),
      ],
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Statisztika – bevétel/kiadás időszakokra
// ─────────────────────────────────────────────────────────────────────────────

class StatisztikaScreen extends StatefulWidget {
  const StatisztikaScreen({super.key});
  @override
  State<StatisztikaScreen> createState() => _StatisztikaScreenState();
}

class _StatisztikaScreenState extends State<StatisztikaScreen> {
  String period = 'Hónap'; // Ma, Hét, Hónap, Negyedév, Év, Egyedi
  DateTimeRange? custom;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTimeRange range;
    switch (period) {
      case 'Ma':
        final start = DateTime(now.year, now.month, now.day);
        range = DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
        break;
      case 'Hét':
        final wd = now.weekday;
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: wd-1));
        range = DateTimeRange(start: start, end: start.add(const Duration(days: 7)));
        break;
      case 'Negyedév':
        final q = ((now.month-1)~/3)+1;
        final startMonth = (q-1)*3+1;
        final start = DateTime(now.year, startMonth, 1);
        range = DateTimeRange(start: start, end: DateTime(now.year, startMonth+3, 1));
        break;
      case 'Év':
        final start = DateTime(now.year, 1, 1);
        range = DateTimeRange(start: start, end: DateTime(now.year+1,1,1));
        break;
      case 'Egyedi':
        range = custom ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month+1, 1));
        break;
      case 'Hónap':
      default:
        final start = DateTime(now.year, now.month, 1);
        range = DateTimeRange(start: start, end: DateTime(now.year, now.month+1, 1));
        break;
    }

    final list = AppState.I.finance.where((e)=> e.date.isAfter(range.start.subtract(const Duration(milliseconds:1))) && e.date.isBefore(range.end)).toList()
      ..sort((a,b)=> a.date.compareTo(b.date));
    final totalRev = list.fold<int>(0, (p,e)=> p+e.revenue);
    final totalExp = list.fold<int>(0, (p,e)=> p+e.expense);
    final net = totalRev-totalExp;

    return Scaffold(
      appBar: AppBar(title: const Text('Statisztika')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: _SummaryCard(title: 'Bevétel', value: _fmtFt(totalRev))),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Kiadás', value: _fmtFt(totalExp))),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Eredmény', value: _fmtFt(net))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Időszak:'), const SizedBox(width: 8),
            DropdownButton<String>(value: period, items: ['Ma','Hét','Hónap','Negyedév','Év','Egyedi'].map((e)=>DropdownMenuItem(value:e, child: Text(e))).toList(), onChanged: (v)=> setState(()=> period = v ?? 'Hónap')),
            if (period=='Egyedi') ...[
              const SizedBox(width: 12),
              FilledButton(onPressed: () async {
                final picked = await showDateRangePicker(context: context, firstDate: DateTime(now.year-3), lastDate: DateTime(now.year+1), initialDateRange: range);
                if (picked!=null) setState(()=> custom = picked);
              }, child: const Text('Tartomány választása')),
            ]
          ]),
          const SizedBox(height: 12),
          Card(child: Column(children: [
            const ListTile(title: Text('Bejegyzések (időrendben)')),
            const Divider(height: 1),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nincs adat az időszakban')),
            ...list.map((e)=> ListTile(
              leading: const Icon(Icons.monetization_on_outlined),
              title: Text('${e.date.toLocal()}  •  Bev: ${_fmtFt(e.revenue)}  •  Ki: ${_fmtFt(e.expense)}'),
              subtitle: Text('Felmerés ID: ${e.surveyId}  •  Rögzítette: ${e.setBy}'),
            ))
          ])),
        ],
      ),
    );
  }

  String _fmtFt(int v) => '${v.toString()} Ft';
}

class _SummaryCard extends StatelessWidget {
  final String title; final String value;
  const _SummaryCard({required this.title, required this.value});
  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(title: Text(title), subtitle: Text(value, style: Theme.of(context).textTheme.titleLarge)));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Engedélyek – admin beállíthatja felhasználónként a menük és jogok láthatóságát
// ─────────────────────────────────────────────────────────────────────────────

class EngedelyekScreen extends StatefulWidget {
  const EngedelyekScreen({super.key});
  @override
  State<EngedelyekScreen> createState() => _EngedelyekScreenState();
}

class _EngedelyekScreenState extends State<EngedelyekScreen> {
  final Map<AppMenu, bool> _tempVisible = { for (final m in AppMenu.values) m : Session.I.perms.visibleMenus.contains(m) };
  bool _tempCalMove = Session.I.perms.canMoveCalendar;
  bool _tempNapiAdd = Session.I.perms.canAddNapiMunka;

  @override
  Widget build(BuildContext context) {
    if (!Session.I.perms.isAdmin) return const _ScaffoldPlaceholder(title: 'Engedélyek – csak admin');
    return Scaffold(
      appBar: AppBar(title: const Text('Engedélyek (demo – aktuális userre)')),
      body: ListView(
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Válaszd ki, mely menük látszanak, és milyen műveletek engedélyezettek.')),
          const ListTile(title: Text('Menüpontok láthatósága')),
          ...AppMenu.values.map((m)=> SwitchListTile(
            title: Text(_menuTitle(m)),
            value: _tempVisible[m] ?? false,
            onChanged: (v)=> setState(()=> _tempVisible[m] = v),
          )),
          const Divider(),
          const ListTile(title: Text('Műveleti jogok')),
          SwitchListTile(title: const Text('Naptárban mozgatás (drag&drop)'), value: _tempCalMove, onChanged: (v)=> setState(()=> _tempCalMove = v)),
          SwitchListTile(title: const Text('Napi munkában helyben hozzáadás'), value: _tempNapiAdd, onChanged: (v)=> setState(()=> _tempNapiAdd = v)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FilledButton(onPressed: (){
              final visible = _tempVisible.entries.where((e)=> e.value).map((e)=> e.key).toSet();
              Session.I.setVisibleMenusForUser(visible);
              Session.I.setCalendarMove(_tempCalMove);
              Session.I.setNapiMunkaAdd(_tempNapiAdd);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Engedélyek frissítve')));
            }, child: const Text('Mentés')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _menuTitle(AppMenu m){
    switch (m) {
      case AppMenu.felmeres: return 'Felmérés';
      case AppMenu.arajanlatok: return 'Árajánlatok';
      case AppMenu.mentettFelmeresek: return 'Mentett felmérések';
      case AppMenu.naptar: return 'Naptár';
      case AppMenu.ugyfelek: return 'Ügyfelek';
      case AppMenu.bevasarloLista: return 'Bevásárló lista';
      case AppMenu.napiMunka: return 'Napi munka';
      case AppMenu.statisztika: return 'Statisztika';
      case AppMenu.engedelyek: return 'Engedélyek';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bejelentkezés/Profil
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final name = TextEditingController(text: 'Teszt Felhasználó');
    bool admin = false;
    return Scaffold(
      appBar: AppBar(title: const Text('Bejelentkezés (demo)')),
      body: StatefulBuilder(builder: (context, setState) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Név')),
          SwitchListTile(title: const Text('Admin jog'), value: admin, onChanged: (v)=> setState(()=> admin = v)),
          const SizedBox(height: 12),
          FilledButton(onPressed: (){ Session.I.loginAs(name: name.text.trim(), admin: admin); Navigator.pop(context); }, child: const Text('Belépés')),
        ]),
      )),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = Session.I.userName ?? 'Ismeretlen';
    final initials = Session.I.avatarInitials ?? 'P';
    final pw = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: const Text('Profilom')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          CircleAvatar(radius: 28, child: Text(initials)),
          const SizedBox(width: 12),
          Expanded(child: Text(user, style: Theme.of(context).textTheme.titleLarge)),
        ]),
        const SizedBox(height: 24),
        TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Új jelszó (demo)')),
        const SizedBox(height: 12),
        FilledButton(onPressed: ()=> ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jelszó frissítve (demo)'))), child: const Text('Mentés')),
        const SizedBox(height: 12),
        TextButton.icon(onPressed: (){ Session.I.logout(); Navigator.pop(context); }, icon: const Icon(Icons.logout), label: const Text('Kijelentkezés')),
      ]),
    );
  }
}

class _ScaffoldPlaceholder extends StatelessWidget {
  final String title;
  const _ScaffoldPlaceholder({required this.title});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text(title)), body: Center(child: Text('$title\n\n(Alkalmazás váz – később bővítjük)', textAlign: TextAlign.center)));
  }
}
