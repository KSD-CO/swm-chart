// Port of lightweight-charts src/model/tick-marks.ts
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

  void setUniformDistribution(bool value) {
    if (value == _uniformDistribution) return;
    _uniformDistribution = value;
    _cache = null;
  }

  void setTimeScalePoints(List<num> times, List<int> weights, int firstChangedPointIndex) {
    _removeMarksSinceIndex(firstChangedPointIndex);
    _cache = null;

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
    if (_cache == null ||
        _cacheMaxIndexesPerMark != maxIndexesPerMark ||
        _cacheCheckIndices != checkIndicesForData ||
        _cacheIndicesWithDataId != indicesWithDataId) {
      _cache = _buildMarksImpl(maxIndexesPerMark, checkIndicesForData ? indicesWithData : null);
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
  List<TickMark> _buildMarksImpl(int maxIndexesPerMark, Set<int>? indicesWithData) {
    bool canBeIncluded(TickMark mark) => indicesWithData == null || indicesWithData.contains(mark.index);
    var marks = <TickMark>[];
    final weights = _marksByWeight.keys.toList()..sort((a, b) => b - a);

    for (final weight in weights) {
      final prevMarks = marks;
      marks = <TickMark>[];

      final prevMarksLength = prevMarks.length;
      var prevMarksPointer = 0;
      final currentWeight = _marksByWeight[weight]!;

      num rightIndex = double.infinity;
      num leftIndex = double.negativeInfinity;
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
