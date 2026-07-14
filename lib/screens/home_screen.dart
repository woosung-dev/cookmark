// 냉파 ① 온보딩/홈 화면 — 인앱브라우저 경고·히어로·사진 올리기 CTA + 하단 탭바(메인↔레시피 북)
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('냉파'),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.info_outline, color: AppColors.muted))],
      ),
      // 웹에서도 앱처럼 보이게 중앙 정렬 + 폭 제한
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: _tab == 0 ? const _OnboardingTab() : const _RecipeBookPlaceholder(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.actionTint,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.action), label: '메인'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark, color: AppColors.action), label: '레시피 북'),
        ],
      ),
    );
  }
}

class _OnboardingTab extends StatelessWidget {
  const _OnboardingTab();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // 인앱브라우저 경고 배너
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.buyBg, borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.buyFg),
            SizedBox(width: 10),
            Expanded(child: Text('카톡 내부 브라우저예요. 크롬·사파리로 열면 더 안정적이에요.',
                style: TextStyle(fontSize: 13, color: AppColors.buyFg))),
          ]),
        ),
        const SizedBox(height: 28),
        Text('냉장고 사진 한 장으로,\n오늘 뭐 해먹을지 끝내요.', style: t.displaySmall),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.goFg),
          const SizedBox(width: 8),
          Expanded(child: Text('출처 있는, 내가 저장한 레시피만 추천해요.', style: t.bodyMedium?.copyWith(color: AppColors.muted))),
        ]),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('냉장고 사진 올리기'),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(foregroundColor: AppColors.action),
            child: const Text('레시피 북 둘러보기'),
          ),
        ),
      ],
    );
  }
}

class _RecipeBookPlaceholder extends StatelessWidget {
  const _RecipeBookPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('레시피 북 (준비 중)', style: TextStyle(color: AppColors.muted)),
    );
  }
}
