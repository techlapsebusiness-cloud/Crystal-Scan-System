const List<int> allowedFrameCounts = <int>[16, 32, 64, 128];

bool isAllowedFrameCount(int value) => allowedFrameCounts.contains(value);
