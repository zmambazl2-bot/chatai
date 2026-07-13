import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../services/health_News_Service.dart';
import 'all_HealthNewsScreen.dart';
import 'newsDetailScreen.dart';

class MedicalNewsWidget extends StatefulWidget {
  const MedicalNewsWidget({super.key});

  @override
  State<MedicalNewsWidget> createState() => _MedicalNewsWidgetState();
}

class _MedicalNewsWidgetState extends State<MedicalNewsWidget> {
  List<HealthNewsItem> news = [];
  bool isLoading = true;


  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    final loadedNews = await HealthNewsService.fetchMedicalNews();
    if (!mounted) return;
    setState(() {
      news = loadedNews;
      isLoading = false;
    });
  }

  Widget _buildImageFallback() {
    return Container(
      width: double.infinity,
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'آخر الأخبار الطبية',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AllHealthNewsScreen(newsList: news),
                    ),
                  );
                },
                child: const Text("عرض الكل"),
              )
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (news.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withOpacity(0.35)),
              ),
              child: const Text(
                'لا توجد أخبار طبية متاحة حالياً. اسحب لتحديث الصفحة وحاول مرة أخرى.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final screenSize = MediaQuery.sizeOf(context);
              final screenWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : screenSize.width;
              final compact = screenWidth < 360;
              final cardHeight = math.min(math.max(screenSize.height * 0.12, compact ? 104.0 : 112.0), 136.0);
              final cardWidth = math.min(math.max(screenWidth * (compact ? 0.86 : 0.76), 220.0), 320.0);
              final imageWidth = math.min(cardWidth * 0.34, 104.0);
              final titleSize = compact ? 12.0 : 13.0;
              final sourceSize = compact ? 10.0 : 10.5;

              return SizedBox(
                height: cardHeight + 8,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: news.map((article) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NewsDetailScreen(news: article),
                            ),
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
                                color: isDarkMode ? Colors.black26 : Colors.grey.withOpacity(0.12),
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
                                child: article.imageUrl.isNotEmpty
                                    ? Image.network(
                                        article.imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildImageFallback(),
                                      )
                                    : _buildImageFallback(),
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
                                          article.title,
                                          maxLines: compact ? 2 : 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            height: 1.15,
                                            fontSize: titleSize,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        article.source,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: sourceSize,
                                          color: Colors.grey,
                                          height: 1.1,
                                        ),
                                      ),
                                    ],
                                ),
                              ),
                                )],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
