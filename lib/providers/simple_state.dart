import 'package:flutter/material.dart';
import '../models/app_user.dart';

class AppState extends ChangeNotifier {
  AppUser? _currentUser;
  int _selectedTab = 0;
  
  AppUser? get currentUser => _currentUser;
  int get selectedTab => _selectedTab;
  
  void setUser(AppUser? user) {
    _currentUser = user;
    notifyListeners();
  }
  
  void setSelectedTab(int index) {
    _selectedTab = index;
    notifyListeners();
  }
}