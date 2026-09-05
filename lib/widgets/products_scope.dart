import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/products_controller.dart';

/// Inherited access to the product catalog.
extension ProductsScope on BuildContext {
  ProductsController? products() => read<ProductsController>();
}
