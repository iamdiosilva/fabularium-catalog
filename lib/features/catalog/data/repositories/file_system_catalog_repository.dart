import '../../../../models/catalog_model.dart';
import '../../../../services/cagalog_scanner.dart';
import '../../domain/repositories/catalog_repository.dart';

class FileSystemCatalogRepository implements CatalogRepository {
  final CatalogScanner scanner;

  FileSystemCatalogRepository({CatalogScanner? scanner})
      : scanner = scanner ?? CatalogScanner();

  @override
  Future<List<CatalogStudio>> loadCatalog(String fabulariumPath) {
    return scanner.scan(fabulariumPath);
  }
}
