import '../../../../models/catalog_model.dart';
import '../entities/catalog_telegram_status.dart';

abstract interface class CatalogTelegramStatusRepository {
  Future<CatalogTelegramStatus> readLocalStatus(CatalogModel model);

  Future<CatalogTelegramStatus> verifyStoredStatus(CatalogModel model);
}
