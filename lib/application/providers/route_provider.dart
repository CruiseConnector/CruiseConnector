import 'package:flutter/foundation.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// Verwaltet die aktuell aktive Route und den Routen-Generierungs-Status.
/// Wird in main.dart als ChangeNotifierProvider eingebunden.
class RouteProvider extends ChangeNotifier {
  RouteResult? _activeRoute;
  bool _isGenerating = false;
  String? _errorMessage;

  /// Die aktuell aktive / angezeigte Route.
  RouteResult? get activeRoute => _activeRoute;

  /// true = Route wird gerade berechnet.
  bool get isGenerating => _isGenerating;

  /// Fehlermeldung falls Generierung fehlgeschlagen.
  String? get errorMessage => _errorMessage;

  /// Setzt eine neu berechnete oder geladene Route als aktiv.
  /// Wird genutzt wenn der User auf eine gespeicherte, vorgeschlagene
  /// oder Community-Route klickt → navigiert zur normalen Cruise-Mode-Page.
  void setActiveRoute(RouteResult route) {
    _activeRoute = route;
    _errorMessage = null;
    notifyListeners();
  }

  /// Setzt den Lade-Status während der Berechnung.
  void setGenerating(bool value) {
    _isGenerating = value;
    notifyListeners();
  }

  /// Setzt eine Fehlermeldung und beendet den Lade-Status.
  void setError(String message) {
    _errorMessage = message;
    _isGenerating = false;
    notifyListeners();
  }

  /// Löscht die aktive Route (z.B. nach Ende der Fahrt).
  void clearRoute() {
    _activeRoute = null;
    _errorMessage = null;
    notifyListeners();
  }
}
