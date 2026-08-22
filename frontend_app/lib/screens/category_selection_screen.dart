import 'package:flutter/material.dart';

import '../core/shop_categories.dart';
import '../core/theme.dart';
import 'registration_screen.dart';

class _CategoryPresentation {
  final String name;
  final String title;
  final String description;
  final String tag;
  final IconData icon;
  final Color accent;

  const _CategoryPresentation({
    required this.name,
    required this.title,
    required this.description,
    required this.tag,
    required this.icon,
    required this.accent,
  });
}

const _categories = <_CategoryPresentation>[
  _CategoryPresentation(name: 'Kirana', title: 'Kirana & Grocery', description: 'Groceries, daily essentials, loose items and household provisions.', tag: 'Popular', icon: Icons.shopping_basket_rounded, accent: Color(0xFFE8F5E9)),
  _CategoryPresentation(name: 'Pharmacy', title: 'Pharmacy & Medical', description: 'Medicines, wellness products, first aid and medical supplies.', tag: 'Healthcare', icon: Icons.local_pharmacy_rounded, accent: Color(0xFFE3F5FF)),
  _CategoryPresentation(name: 'Doctor Prescription', title: 'Doctor & Prescription', description: 'Voice-assisted prescription drafting and patient records.', tag: 'Clinical', icon: Icons.medical_services_rounded, accent: Color(0xFFF4E8FF)),
  _CategoryPresentation(name: 'Dairy', title: 'Dairy & Fresh', description: 'Milk, curd, paneer and other fresh daily products.', tag: 'Fresh', icon: Icons.egg_alt_rounded, accent: Color(0xFFE5F7FF)),
  _CategoryPresentation(name: 'Hardware', title: 'Hardware & Tools', description: 'Construction tools, electrical fittings, pipes and hardware items.', tag: 'Industrial', icon: Icons.build_rounded, accent: Color(0xFFF1F4F6)),
  _CategoryPresentation(name: 'Bakery', title: 'Bakery & Cakes', description: 'Cakes, bread, pastries, snacks and made-to-order products.', tag: 'Freshly baked', icon: Icons.cake_rounded, accent: Color(0xFFFFE9F1)),
  _CategoryPresentation(name: 'Fast Food', title: 'Fast Food & Cafe', description: 'Quick-service menus, meals, beverages and takeaway orders.', tag: 'Food', icon: Icons.fastfood_rounded, accent: Color(0xFFFFF1E6)),
  _CategoryPresentation(name: 'Stationery', title: 'Stationery & Books', description: 'School supplies, office essentials and books.', tag: 'Everyday', icon: Icons.edit_note_rounded, accent: Color(0xFFEAF0FF)),
  _CategoryPresentation(name: 'Clothing', title: 'Clothing & Fashion', description: 'Garments, accessories and size-based items.', tag: 'Retail', icon: Icons.checkroom_rounded, accent: Color(0xFFFFEEF6)),
  _CategoryPresentation(name: 'General', title: 'General Store', description: 'A flexible setup for mixed retail and daily-needs shops.', tag: 'Flexible', icon: Icons.storefront_rounded, accent: Color(0xFFF4F4F4)),
  _CategoryPresentation(name: 'Other', title: 'Other Business', description: 'Start with a flexible catalog and customize it for your business.', tag: 'Flexible', icon: Icons.auto_awesome_rounded, accent: Color(0xFFFFF7DF)),
];

class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() => _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  late final PageController _pageController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: .84);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _continue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrationScreen(initialShopCategory: _categories[_selectedIndex].name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = _categories[_selectedIndex];
    return Scaffold(
      backgroundColor: const Color(0xFFFAFCFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFCFF),
        elevation: 0,
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
        title: const Column(
          children: [
            Text('STEP 1 OF 2', style: TextStyle(color: AppColors.primaryGreen, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            SizedBox(height: 3),
            Text('Choose Category', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 24, 28, 10),
              child: Column(
                children: [
                  Text('What type of shop do you run?', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w900)),
                  SizedBox(height: 14),
                  Text('Swipe to explore categories. Your billing AI will be customized for your store.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppColors.textGrey, height: 1.35)),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _categories.length,
                onPageChanged: (index) => setState(() => _selectedIndex = index),
                itemBuilder: (context, index) => _CategoryCard(category: _categories[index], selected: index == _selectedIndex),
              ),
            ),
            _PageDots(selectedIndex: _selectedIndex, total: _categories.length),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _categories[index];
                  final selected = index == _selectedIndex;
                  return ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: AppColors.primaryGreen,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: selected ? AppColors.primaryGreen : const Color(0xFFDDE3EA)),
                    label: Text(item.name, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textGrey)),
                    avatar: Icon(item.icon, size: 18, color: selected ? Colors.white : AppColors.primaryGreen),
                    onSelected: (_) => _pageController.animateToPage(index, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 18),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _continue,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text('Continue as ${category.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final _CategoryPresentation category;
  final bool selected;

  const _CategoryCard({required this.category, required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1 : .94,
      duration: const Duration(milliseconds: 220),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 22, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: selected ? AppColors.primaryGreen : const Color(0xFFE1E7ED), width: selected ? 3 : 1),
          boxShadow: [BoxShadow(color: AppColors.primaryGreen.withValues(alpha: selected ? .16 : .04), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  Container(decoration: BoxDecoration(color: category.accent, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)))),
                  Center(child: Image.asset(getShopCategoryImage(category.name), fit: BoxFit.contain, width: 205, height: 180)),
                  Positioned(top: 16, left: 16, child: _Pill(icon: category.icon, label: category.tag)),
                  if (selected) const Positioned(top: 16, right: 16, child: CircleAvatar(radius: 20, backgroundColor: AppColors.primaryGreen, child: Icon(Icons.check_rounded, color: Colors.white))),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(category.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 9),
                    Text(category.description, style: const TextStyle(fontSize: 16, height: 1.35, color: AppColors.textGrey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(18)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: Colors.white), const SizedBox(width: 5), Text(label.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: .5))]),
  );
}

class _PageDots extends StatelessWidget {
  final int selectedIndex;
  final int total;
  const _PageDots({required this.selectedIndex, required this.total});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(total, (index) => AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 8,
      width: index == selectedIndex ? 26 : 8,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(color: index == selectedIndex ? AppColors.primaryGreen : const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(8)),
    )),
  );
}
