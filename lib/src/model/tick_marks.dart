// Port of lightweight-charts src/model/tick-marks.ts
import 'dart:math' as math;

class TickMark {
  const TickMark(this.index, this.time, this.weight);

  final int index;
  final num time;
  final int weight;
}

class TickMarks {
  final Map<int, List<TickMark>> _marksByWeight = {};
  int? _cacheMaxIndexesPerMark;
  int? _cacheIndicesWithDataId;
  bool? _cacheCheckIndices;
  List<TickMark>? _cache;
  bool _uniformDistribution = false;

  /// Points were only appended from this index since [_cache] was built.
  int? _appendedFrom;
  int _pointsCount = 0;

  void setUniformDistribution(bool value) {
    if (value == _uniformDistribution) return;
    _uniformDistribution = value;
    _cache = null;
  }

  void setTimeScalePoints(List<num> times, List<int> weights, int firstChangedPointIndex) {
    _removeMarksSinceIndex(firstChangedPointIndex);
    if (_cache != null && firstChangedPointIndex == _pointsCount && firstChangedPointIndex > 0) {
      // Pure append (a new bar): the cache stays valid except near the end.
      _appendedFrom = math.min(_appendedFrom ?? firstChangedPointIndex, firstChangedPointIndex);
    } else {
      _cache = null;
      _appendedFrom = null;
    }
    _pointsCount = times.length;

    for (var index = firstChangedPointIndex; index < times.length; ++index) {
      _marksByWeight.putIfAbsent(weights[index], () => []).add(TickMark(index, times[index], weights[index]));
    }
  }

  /// With [checkIndicesForData], marks at indices missing from
  /// [indicesWithData] (whitespace) are skipped.
  List<TickMark> build(
    double spacing,
    double maxWidth, {
    bool checkIndicesForData = false,
    Set<int> indicesWithData = const {},
    int indicesWithDataId = 0,
  }) {
    final maxIndexesPerMark = (maxWidth / spacing).ceil();
    final filter = checkIndicesForData ? indicesWithData : null;
    final sameParams = _cache != null &&
        _cacheMaxIndexesPerMark == maxIndexesPerMark &&
        _cacheCheckIndices == checkIndicesForData &&
        _cacheIndicesWithDataId == indicesWithDataId;
    if (sameParams && _appendedFrom != null) {
      _cache = _rebuildTail(maxIndexesPerMark, filter, _appendedFrom!);
      _appendedFrom = null;
    } else if (!sameParams) {
      _cache = _buildMarksImpl(maxIndexesPerMark, filter);
      _appendedFrom = null;
      _cacheMaxIndexesPerMark = maxIndexesPerMark;
      _cacheCheckIndices = checkIndicesForData;
      _cacheIndicesWithDataId = indicesWithDataId;
    }
    return _cache!;
  }

  void _removeMarksSinceIndex(int sinceIndex) {
    if (sinceIndex == 0) {
      _marksByWeight.clear();
      return;
    }

    final weightsToClear = <int>[];
    _marksByWeight.forEach((weight, marks) {
      if (sinceIndex <= marks[0].index) {
        weightsToClear.add(weight);
      } else {
        marks.removeRange(_lowerBound(marks, sinceIndex), marks.length);
      }
    });
    weightsToClear.forEach(_marksByWeight.remove);
  }

  /// Recomputes the selection after points were appended from
  /// [appendedFrom], keeping the cached prefix. Exact: appending at the
  /// right end can only change decisions within one label spacing per
  /// weight level of the end, so marks before
  /// `appendedFrom - (levels + 1) * maxIndexesPerMark` keep their fate.
  List<TickMark> _rebuildTail(int maxIndexesPerMark, Set<int>? indicesWithData, int appendedFrom) {
    final cutoff = appendedFrom - (_marksByWeight.length + 1) * maxIndexesPerMark;
    if (cutoff <= 0 || _uniformDistribution) return _buildMarksImpl(maxIndexesPerMark, indicesWithData);
    final old = _cache!;
    final prefix = old.sublist(0, _lowerBound(old, cutoff));

    // Nearest kept prefix mark of each weight or heavier: the left
    // neighbour the greedy pass would see when it reaches the tail.
    num leftmostAtLeast(int weight) {
      for (var i = prefix.length - 1; i >= 0; i--) {
        if (prefix[i].weight >= weight) return prefix[i].index;
      }
      return double.negativeInfinity;
    }

    final tail = _buildMarksImpl(
      maxIndexesPerMark,
      indicesWithData,
      fromIndex: cutoff,
      initialLeft: leftmostAtLeast,
    );
    return [...prefix, ...tail];
  }

  static int _lowerBound(List<TickMark> marks, int index) {
    var lo = 0;
    var hi = marks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (marks[mid].index < index) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Greedy selection from the heaviest weight down: a mark is kept if it is
  /// at least [maxIndexesPerMark] bars away from its already-kept neighbours.
  ///
  /// With [fromIndex], only marks at or after it are considered, and each
  /// weight level starts from [initialLeft] instead of minus infinity.
  List<TickMark> _buildMarksImpl(
    int maxIndexesPerMark,
    Set<int>? indicesWithData, {
    int fromIndex = 0,
    num Function(int weight)? initialLeft,
  }) {
    bool canBeIncluded(TickMark mark) => indicesWithData == null || indicesWithData.contains(mark.index);
    var marks = <TickMark>[];
    final weights = _marksByWeight.keys.toList()..sort((a, b) => b - a);

    for (final weight in weights) {
      final prevMarks = marks;
      marks = <TickMark>[];

      final prevMarksLength = prevMarks.length;
      var prevMarksPointer = 0;
      final allOfWeight = _marksByWeight[weight]!;
      final currentWeight = fromIndex == 0 ? allOfWeight : allOfWeight.sublist(_lowerBound(allOfWeight, fromIndex));

      num rightIndex = double.infinity;
      num leftIndex = initialLeft?.call(weight) ?? double.negativeInfinity;
      for (final mark in currentWeight) {
        final currentIndex = mark.index;

        // Move every already-kept mark left of the current one to the result.
        while (prevMarksPointer < prevMarksLength) {
          final lastMark = prevMarks[prevMarksPointer];
          final lastIndex = lastMark.index;
          if (lastIndex < currentIndex && canBeIncluded(lastMark)) {
            prevMarksPointer++;
            marks.add(lastMark);
            leftIndex = lastIndex;
            rightIndex = double.infinity;
          } else {
            rightIndex = lastIndex;
            break;
          }
        }

        if (rightIndex - currentIndex >= maxIndexesPerMark &&
            currentIndex - leftIndex >= maxIndexesPerMark &&
            canBeIncluded(mark)) {
          marks.add(mark);
          leftIndex = currentIndex;
        } else if (_uniformDistribution) {
          return prevMarks;
        }
      }

      for (; prevMarksPointer < prevMarksLength; prevMarksPointer++) {
        if (canBeIncluded(prevMarks[prevMarksPointer])) marks.add(prevMarks[prevMarksPointer]);
      }
    }

    return marks;
  }
}
