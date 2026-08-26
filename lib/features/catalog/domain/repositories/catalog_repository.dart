import '../../../../models/catalog_model.dart';

abstract interface class CatalogRepository {
  Future<List<CatalogStudio>> loadCatalog(String fabulariumPath);
}
