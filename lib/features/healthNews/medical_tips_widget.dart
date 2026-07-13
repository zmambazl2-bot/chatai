import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/health_News_Service.dart';
import 'all_HealthNewsScreen.dart';
import 'newsDetailScreen.dart';

class MedicalTipsWidget extends StatefulWidget {
  const MedicalTipsWidget({super.key});

  @override
  State<MedicalTipsWidget> createState() => _MedicalTipsWidgetState();
}

class _MedicalTipsWidgetState extends State<MedicalTipsWidget> {
  List<HealthNewsItem> chronicTips = [];
  List<HealthNewsItem> nutritionTips = [];
  List<HealthNewsItem> preventionTips = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTips();
  }

  Future<void> _loadTips() async {
    chronicTips = await HealthNewsService.fetchChronicDiseaseTips();
    nutritionTips = await HealthNewsService.fetchNutritionTips();
    preventionTips = await HealthNewsService.fetchPreventionTips();

    setState(() => isLoading = false);
  }

  Widget _buildHorizontalTips(String title, List<HealthNewsItem> tips) {
    if (tips.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : screenSize.width;
        final compact = width < 360;
        final cardHeight = math.min(math.max(screenSize.height * 0.12, compact ? 104.0 : 112.0), 136.0);
        final cardWidth = math.min(math.max(width * (compact ? 0.86 : 0.76), 220.0), 320.0);
        final imageWidth = math.min(cardWidth * 0.34, 104.0);
        final titleSize = compact ? 12.0 : 13.0;
        final sourceSize = compact ? 10.0 : 10.5;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 14 : 15,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AllHealthNewsScreen(newsList: tips)),
                      );
                    },
                    child: const Text("عرض الكل"),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: cardHeight + 8,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: tips.map((tip) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => NewsDetailScreen(news: tip)),
                        );
                      },
                      child: Container(
                        width: cardWidth,
                        height: cardHeight,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.grey[900] : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDarkMode ? .18 : .06),
                              blurRadius: isDarkMode ? 0 : 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: imageWidth,
                              child: tip.imageUrl.isNotEmpty
                                  ? Image.network(
                                      tip.imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _imageFallback(),
                                    )
                                  : _imageFallback(),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 8 : 10,
                                  vertical: compact ? 7 : 9,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        tip.title,
                                        maxLines: compact ? 2 : 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: titleSize,
                                          height: 1.15,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      tip.source,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: sourceSize, color: Colors.grey, height: 1.1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _imageFallback() {
    return Container(
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHorizontalTips('نصائح للأمراض المزمنة', chronicTips),

        const SizedBox(height: 20),

        _buildHorizontalTips('الغذاء المفيد', nutritionTips),

        const SizedBox(height: 20),

        _buildHorizontalTips('الوقاية من الأمراض المعدية', preventionTips),
      ],
    );
  }
}
