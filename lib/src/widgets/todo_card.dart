import 'package:flutter/material.dart';

import '../services/todo_service.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';

/// The to-do card on the digest page.
///
/// A real list: add a thing, tick it off, delete it. Persisted to the device
/// by [TodoService], so it survives a restart — a to-do list that forgets
/// itself is a piece of paper.
///
/// Two things this deliberately is not:
///
///  * **Not a modal.** A dialog would hide the rest of the page and the
///    keyboard would land on top of it.
///  * **Not a text area.** One line per item, because a wall-mounted tablet
///    is not where you write paragraphs.
class TodoCard extends StatefulWidget {
  const TodoCard({
    super.key,
    required this.service,
    required this.metrics,
    required this.palette,
    required this.type,
  });

  final TodoService service;
  final NestMetrics metrics;
  final AmbientPalette palette;
  final NestType type;

  @override
  State<TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends State<TodoCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // Clear first: the write is async, and leaving the text in the field
    // while it persists makes it look like the add failed.
    _controller.clear();
    await widget.service.add(text);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final p = widget.palette;
    final type = widget.type;
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final items = widget.service.items;
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(m.px(20)),
          ),
          padding: EdgeInsets.fromLTRB(m.px(16), m.px(14), m.px(16), m.px(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'To do',
                    style: type.caption(color: p.onSurfaceStrong),
                  ),
                  const Spacer(),
                  if (widget.service.openCount > 0)
                    Text(
                      '${widget.service.openCount} left',
                      style: type.caption(color: p.onSurfaceVariant),
                    ),
                ],
              ),
              SizedBox(height: m.px(8)),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing to do',
                          style: type.caption(color: p.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        // The list is inside a card, so it must not also
                        // scroll the page.
                        physics: const ClampingScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (context, i) => _row(items[i], m, p, type),
                      ),
              ),
              SizedBox(height: m.px(8)),
              _input(m, p, type),
            ],
          ),
        );
      },
    );
  }

  Widget _row(TodoItem item, NestMetrics m, AmbientPalette p, NestType type) {
    return Padding(
      padding: EdgeInsets.only(bottom: m.px(6)),
      child: Row(
        children: [
          // The tick. A filled circle with a check, and a hollow one for
          // something outstanding.
          GestureDetector(
            key: ValueKey('todo-tick-${item.id}'),
            onTap: () => widget.service.toggle(item.id),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: m.px(20),
              height: m.px(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.done
                    ? p.onSurface
                    : p.onSurface.withValues(alpha: 0.10),
                border: item.done
                    ? null
                    : Border.all(
                        color: p.onSurface.withValues(alpha: 0.35),
                        width: m.px(1.5),
                      ),
              ),
              child: item.done
                  ? Icon(
                      Icons.check,
                      size: m.px(13),
                      color: p.surface,
                    )
                  : null,
            ),
          ),
          SizedBox(width: m.px(10)),
          Expanded(
            child: Text(
              item.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: type.caption(
                color: item.done ? p.onSurfaceVariant : p.onSurfaceStrong,
              ).copyWith(
                decoration: item.done ? TextDecoration.lineThrough : null,
                decorationColor: p.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(width: m.px(6)),
          // Delete. Small, quiet, and out of the way of the text.
          GestureDetector(
            key: ValueKey('todo-delete-${item.id}'),
            onTap: () => widget.service.remove(item.id),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.all(m.px(4)),
              child: Icon(
                Icons.close,
                size: m.px(15),
                color: p.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(NestMetrics m, AmbientPalette p, NestType type) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('todo-input'),
            controller: _controller,
            focusNode: _focus,
            onSubmitted: (_) => _submit(),
            textInputAction: TextInputAction.done,
            maxLines: 1,
            style: type.caption(color: p.onSurfaceStrong),
            cursorColor: p.onSurface,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add an item',
              hintStyle: type.caption(color: p.onSurfaceVariant),
              contentPadding: EdgeInsets.symmetric(
                horizontal: m.px(10),
                vertical: m.px(8),
              ),
              filled: true,
              fillColor: p.onSurface.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(m.px(10)),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(m.px(10)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(m.px(10)),
                borderSide: BorderSide(
                  color: p.onSurface.withValues(alpha: 0.35),
                  width: m.px(1.5),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: m.px(6)),
        GestureDetector(
          key: const ValueKey('todo-add'),
          onTap: _submit,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: m.px(34),
            height: m.px(34),
            decoration: BoxDecoration(
              color: p.onSurface,
              borderRadius: BorderRadius.circular(m.px(10)),
            ),
            child: Icon(
              Icons.add,
              size: m.px(18),
              color: p.surface,
            ),
          ),
        ),
      ],
    );
  }
}
