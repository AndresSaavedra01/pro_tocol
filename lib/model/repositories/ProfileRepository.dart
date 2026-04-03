import 'package:isar/isar.dart';
import 'package:pro_tocol/model/daos/ProfileDAO.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

class ProfileRepository {
  final ProfileDAO _profileDAO;

  // Estructura de datos en memoria para acceso rápido
  List<Profile> _profiles = [];

  ProfileRepository(this._profileDAO);

  // Getter para obtener la copia actual de los datos
  List<Profile> get profiles => List.unmodifiable(_profiles);

  // Carga inicial desde la DB a la memoria
  Future<void> init() async {
    _profiles = await _profileDAO.getAllProfiles();
  }

  // Guardar y actualizar memoria
  Future<void> addProfile(Profile profile) async {
    await _profileDAO.saveProfile(profile);
    // Recargamos o añadimos a la lista para mantener consistencia
    if (!_profiles.any((p) => p.id == profile.id)) {
      _profiles.add(profile);
    }
  }

  // Eliminar y actualizar memoria
  Future<void> removeProfile(Id id) async {
    final success = await _profileDAO.deleteProfile(id);
    if (success) {
      _profiles.removeWhere((p) => p.id == id);
    }
  }

  // Buscar en la estructura de datos (sin ir a la DB)
  Profile? findInCache(Id id) {
    try {
      return _profiles.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}