
import 'package:isar/isar.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

class ProfileDAO {
  final Isar isar;

  ProfileDAO(this.isar);

  // Guardar o actualizar un perfil
  Future<void> saveProfile(Profile profile) async {
    await isar.writeTxn(() async {
      await isar.profiles.put(profile);
    });
  }

  // Obtener todos los perfiles con sus servidores cargados
  Future<List<Profile>> getAllProfiles() async {
    final profiles = await isar.profiles.where().findAll();
    for (var profile in profiles) {
      await profile.servers.load();
    }
    return profiles;
  }

  // Buscar un perfil por ID
  Future<Profile?> getProfileById(Id id) async {
    final profile = await isar.profiles.get(id);
    if (profile != null) {
      await profile.servers.load();
    }
    return profile;
  }

  // Eliminar un perfil
  Future<bool> deleteProfile(Id id) async {
    return await isar.writeTxn(() async {
      return await isar.profiles.delete(id);
    });
  }

  // Vincular un servidor a un perfil existente
  Future<void> addServerToProfile(Id profileId, ServerConfig server) async {
    final profile = await isar.profiles.get(profileId);
    if (profile != null) {
      await isar.writeTxn(() async {
        await isar.serverConfigs.put(server); // Guardar el servidor primero
        profile.servers.add(server);
        await profile.servers.save(); // Persistir la relación
      });
    }
  }
}