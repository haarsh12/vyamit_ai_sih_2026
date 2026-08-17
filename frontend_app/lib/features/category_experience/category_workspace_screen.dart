import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'category_experience.dart';

/// Shared building block for category-specific operational pages.
///
/// The data and labels come from each business category's definition, keeping
/// the layout consistent while allowing a category to have different pages and
/// actions without copying a complete screen for every shop type.
class CategoryWorkspaceScreen extends StatelessWidget {
  final String shopCategory;
  final CategoryWorkspace workspace;

  const CategoryWorkspaceScreen({
    super.key,
    required this.shopCategory,
    required this.workspace,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(workspace.title),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textBlack,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  child: Icon(workspace.icon, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopCategory,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        workspace.description,
                        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Category tools',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...workspace.actions.map(
            (action) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.lightGreenBg,
                  child: Icon(action.icon, color: AppColors.primaryGreen),
                ),
                title: Text(action.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(action.description),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${action.title} is ready for this $shopCategory workspace.')),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Inventory, AI context, and voice matching stay inside the selected category. Your Dashboard and Profile remain shared across all categories.',
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }
}
