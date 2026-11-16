import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';

class ErrorView extends StatelessWidget {
  const ErrorView(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            ],
          ]),
        ),
      );
}

class Poster extends StatelessWidget {
  const Poster(this.url, {super.key, this.radius = 10});
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.white10,
      alignment: Alignment.center,
      child: const Icon(Icons.movie_outlined, color: Colors.white38),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            ),
    );
  }
}

class MovieCard extends StatelessWidget {
  const MovieCard(this.movie, {super.key});
  final Movie movie;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/detail/${movie.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            Poster(movie.cover),
            if (movie.score != 'N/A' && movie.score != '0' && movie.score != '0.0')
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(movie.score, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (movie.year != 'N/A')
          Text(movie.year,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ]),
    );
  }
}
