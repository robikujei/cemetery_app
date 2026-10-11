import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cemetery_app/core/theme.dart';
import 'package:cemetery_app/models/app_user.dart';
import 'package:cemetery_app/providers/session_providers.dart';
import 'package:cemetery_app/screens/auth/login_screen.dart';
import 'package:cemetery_app/screens/auth/register_screen.dart';
import 'package:cemetery_app/screens/visitor/visitor_shell_screen.dart';
import 'package:cemetery_app/screens/visitor/visitor_search_screen.dart';
import 'package:cemetery_app/screens/visitor/visitor_qr_with_grave_screen.dart';
import 'package:cemetery_app/screens/visitor/visitor_history_screen.dart';
import 'package:cemetery_app/screens/admin/admin_shell_screen.dart';
import 'package:cemetery_app/screens/lot_owner/lot_owner_home_screen.dart';
import 'package:cemetery_app/screens/guard/qr_scanner_screen.dart';

const uid='00000000-0000-4000-8000-000000000001';
final user={'user_id':uid,'id':uid,'name':'Demo Visitor','email':'visitor@example.invalid','role':'visitor','phone':'','created_at':'2026-01-01T00:00:00Z','total_amount':0};
final lot={'lot_id':1,'lot_number':'024','lot_label':'024','block_number':'A','lot_class_type':'Regular Lot','status':'Occupied','price':23153.0,'x_coord':null,'y_coord':null};
final burial={'burial_id':1,'name_of_deceased':'Maria Santos','birth_date':'1945-05-12','death_date':'2021-03-18','burial_date':'2021-03-22','lot_id':1,'lot_location_no':'01','cemetery_lot':lot};
final log={'log_id':1,'user_id':uid,'time_in':'2026-10-09T08:30:00','method':'QR','burial':burial,'user':user,'users':user};
final config=jsonDecode(File('capture-config.json').readAsStringSync());
final dark=config['dark'] as bool;
final shots=<Map<String,dynamic>>[];
final boundary=GlobalKey();

Future<http.Response> offline(http.Request request) async {
  final table=request.url.pathSegments.last;
  if(request.url.path.contains('/auth/')) {
    return http.Response(jsonEncode({'access_token':'demo.local.only','refresh_token':'demo','token_type':'bearer','expires_in':360000,'user':{'id':uid,'aud':'authenticated','role':'authenticated','email':'visitor@example.invalid','app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}}),200,request:request,headers:{'content-type':'application/json'});
  }
  List<dynamic> rows=switch(table){'users'=>[user],'burial_record'=>[burial],'cemetery_lot'=>[lot],'visitor_log'=>[log],'lot_ownership'=>[{'ownership_id':1,'total_months':12,'months_paid':3,'start_date':'2026-07-01','status':'Active','cemetery_lot':lot,'transaction_history':[],'user':user}],_=>[]};
  if(table=='cemetery_lot' && request.url.queryParameters['status']=='eq.Available')rows=[{...lot,'lot_id':2,'lot_number':'025','lot_label':'025','status':'Available'}];
  if(int.tryParse(request.url.queryParameters['offset']??'0')!>0)rows=[];
  final single=request.headers['accept']?.contains('vnd.pgrst.object')??false;
  return http.Response(jsonEncode(single?(rows.isEmpty?null:rows.first):rows),200,request:request,headers:{'content-type':'application/json','content-range':'0-${rows.isEmpty?0:rows.length-1}/${rows.length}'});
}
Future<void> settle(WidgetTester tester) async {
  for(var i=0;i<25;i++) {await tester.pump(const Duration(milliseconds:100));}
}
Future<void> capture(WidgetTester tester,String name) async {
  await settle(tester);
  final render=boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;

  final file='${dark?'dark':'light'}-${name.replaceAll(' ','-').toLowerCase()}.png';
  final output=Directory(config['output']);output.createSync(recursive:true);
  await tester.runAsync(() async {final image=await render.toImage(pixelRatio:1.5);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);File('${output.path}/$file').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();});
  final controls=<Map<String,dynamic>>[];
  for(final element in find.byType(Text).evaluate()) {
    final widget=element.widget as Text;final text=widget.data;if(text==null)continue;
    final obj=element.findRenderObject();if(obj is! RenderBox || !obj.hasSize)continue;
    final p=obj.localToGlobal(Offset.zero);if(p.dy<0||p.dy>=tester.view.physicalSize.height||p.dx<0)continue;
    controls.add({'text':text,'x':p.dx,'y':p.dy,'w':obj.size.width,'h':obj.size.height});
  }
  for(final element in find.byType(IconButton).evaluate()) {
    final widget=element.widget as IconButton;final obj=element.findRenderObject();if(obj is! RenderBox||!obj.hasSize)continue;
    final icon=widget.icon;final p=obj.localToGlobal(Offset.zero);
    controls.add({'text':'icon:${widget.tooltip??(icon is Icon?icon.icon?.codePoint.toString():'')}','x':p.dx,'y':p.dy,'w':obj.size.width,'h':obj.size.height});
  }
  shots.add({'name':name,'theme':dark?'Dark':'Light','file':file,'width':tester.view.physicalSize.width,'height':tester.view.physicalSize.height,'controls':controls});
  print('CAPTURED $name');
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    for(final family in ['Roboto','Ahem','Segoe UI','MaterialIcons']){final font=FontLoader(family);for(final file in family=='MaterialIcons'?['materialicons-regular.otf']:['roboto-regular.ttf','roboto-medium.ttf','roboto-bold.ttf']){font.addFont(File('F:/src/flutter/bin/cache/artifacts/material_fonts/$file').readAsBytes().then((b)=>ByteData.sublistView(b)));}await font.load();}
    await Supabase.initialize(url:'https://prototype.invalid',anonKey:'offline-demo',httpClient:MockClient(offline),authOptions:const FlutterAuthClientOptions(autoRefreshToken:false,localStorage:EmptyLocalStorage()));
    await Supabase.instance.client.auth.signInWithPassword(email:'visitor@example.invalid',password:'offline-only');
  });
  testWidgets('capture actual screens with offline fixtures',(tester) async {
    tester.view.devicePixelRatio=1;tester.view.physicalSize=const Size(480,1000);
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final router=GoRouter(initialLocation:'/login',routes:[
      GoRoute(path:'/login',builder:(_,__)=>const LoginScreen()),
      GoRoute(path:'/register',builder:(_,__)=>const RegisterScreen()),
      GoRoute(path:'/visitor',builder:(_,__)=>const VisitorShellScreen()),
      GoRoute(path:'/search',builder:(_,__)=>const VisitorSearchScreen()),
      GoRoute(path:'/history',builder:(_,__)=>const VisitorHistoryScreen()),
      GoRoute(path:'/grave-qr',builder:(_,__)=>const VisitorQrWithGraveScreen(burialId:1,deceasedName:'Maria Santos',lotNumber:'024',blockName:'Block A')),
      GoRoute(path:'/admin',builder:(_,__)=>const AdminShellScreen()),
      GoRoute(path:'/owner',builder:(_,__)=>const LotOwnerHomeScreen()),
      GoRoute(path:'/gate',builder:(_,__)=>const QrScannerScreen()),
    ]);
    await tester.pumpWidget(ProviderScope(overrides:[sessionProvider.overrideWith((ref)=>const AppUser(id:uid,displayName:'Demo Visitor',role:UserRole.visitor))],child:RepaintBoundary(key:boundary,child:MaterialApp.router(debugShowCheckedModeBanner:false,theme:dark?ThemeData(useMaterial3:true,fontFamily:'Roboto',colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF335538),brightness:Brightness.dark)):AppTheme.light(),routerConfig:router))));
    await capture(tester,'Login');
    router.go('/register');await capture(tester,'Register');
    router.go('/visitor');await capture(tester,'Visitor Home');
    for(final item in [('Map','Visitor Map'),('QR','Visitor QR'),('Profile','Visitor Profile')]){await tester.tap(find.text(item.$1).last);await capture(tester,item.$2);}
    await tester.tap(find.text('Change Name'));await capture(tester,'Change Name');await tester.tap(find.text('Cancel'));await settle(tester);
    await tester.tap(find.text('Change Password').first);await capture(tester,'Change Password');await tester.tap(find.text('Cancel'));await settle(tester);
    router.go('/search');await capture(tester,'Search Results');
    await tester.enterText(find.byType(TextField).first,'no matching name');await capture(tester,'Search Empty');
    router.go('/grave-qr');await capture(tester,'Grave QR');
    router.go('/history');await capture(tester,'Visit History');
    router.go('/owner');await capture(tester,'Owner My Lots');
    await tester.tap(find.text('Shop Lots'));await capture(tester,'Owner Shop Lots');
    await tester.tap(find.text('Inquire').first);await capture(tester,'Owner Inquiry');await tester.tap(find.text('Close'));await settle(tester);
    await tester.tap(find.byTooltip('Edit Profile'));await capture(tester,'Owner Edit Profile');
    router.go('/gate');await capture(tester,'Gate Scanner');await tester.tap(find.text("Today's Visitors"));await capture(tester,'Gate Visitors');
    router.go('/admin');tester.view.physicalSize=const Size(1440,1000);await capture(tester,'Admin Dashboard');
    await tester.tap(find.byTooltip('Menu').first);await capture(tester,'Admin Drawer');
    for(final item in [('Burial Records','Admin Burial Records'),('Lots','Admin Lots'),('Visitor Logs','Admin Visitor Logs'),('Reports','Admin Reports'),('Audit Trail','Admin Audit Trail'),('Cemetery Map','Admin Mapping Tool'),('User Management','Admin User Management')]){
      final target=find.text(item.$1);if(target.evaluate().isEmpty){print('SKIPPED ${item.$1}');continue;}
      await tester.tap(target.last);await capture(tester,item.$2);
      if(item.$2=='Admin Burial Records'){await tester.tap(find.text('Add New Burial'));await capture(tester,'Add Burial');await tester.tap(find.text('Cancel').last);await settle(tester);}
      if(item.$2=='Admin User Management'){await tester.tap(find.text('Add User'));await capture(tester,'Add User');await tester.tap(find.text('Cancel').last);await settle(tester);}
      await tester.tap(find.byTooltip('Menu').first);await settle(tester);
    }
    await tester.pumpWidget(const SizedBox());await tester.pump(const Duration(seconds:2));router.dispose();
    debugDefaultTargetPlatformOverride=null;
    File('${config['output']}/${dark?'dark':'light'}-manifest.json').writeAsStringSync(jsonEncode(shots));
  },timeout:const Timeout(Duration(minutes:5)));
}
