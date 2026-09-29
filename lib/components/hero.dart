// Required for the rotation angle
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MyHeroWidget extends StatefulWidget {
  const MyHeroWidget({super.key});

  @override
  State<MyHeroWidget> createState() => _MyHeroWidgetState();
}

class _MyHeroWidgetState extends State<MyHeroWidget>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _rotateController;
  late Animation<double> _floatingAnim;

  String appVersion = '';

  @override
  void initState() {
    super.initState();

    getAppVersion().then((value) => setState(() => appVersion = value));

    // Continuous Floating Animation
    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _floatingAnim = CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOutBack,
    );

    // One-shot Rotation Animation (Triggered on Tap)
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
  }

  void _handleTap() {
    if (!_rotateController.isAnimating) {
      _rotateController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return Hero(
      tag: 'title',
      child: Column(
        children: [
          GestureDetector(
            onTap: _handleTap,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Floating Tool Icons
                _buildFloatingIcon(CupertinoIcons.settings,
                    top: -10, left: -40, delay: 0.0),
                _buildFloatingIcon(CupertinoIcons.wrench,
                    bottom: 20, right: -45, delay: 0.5),
                _buildFloatingIcon(CupertinoIcons.hammer_fill,
                    top: 30, left: -50, delay: 0.2),

                // Main Logo with Dual Animation (Scale + Rotation)
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.05).animate(_floatingAnim),
                  child: RotationTransition(
                    turns: Tween(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                          parent: _rotateController, curve: Curves.elasticOut),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/icons/icon.png',
                        height: 85,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Typography
          Text(
            'BSAT',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
              // color: theme.textTheme.displayLarge?.color,
            ),
          ),

          const SizedBox(height: 12),

          // Version Badge (Pill Style)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
              border:
                  Border.all(color: primary.withValues(alpha: 0.2), width: 1),
            ),
            child: Text(
              'VERSION $appVersion',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingIcon(IconData icon,
      {double? top,
      double? bottom,
      double? left,
      double? right,
      required double delay}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: FadeTransition(
        opacity: Tween(begin: 0.3, end: 0.7).animate(_floatingAnim),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: Offset(0, 0.12 + (delay * 0.1)),
          ).animate(_floatingAnim),
          child: Icon(icon,
              size: 24,
              color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
        ),
      ),
    );
  }
}
