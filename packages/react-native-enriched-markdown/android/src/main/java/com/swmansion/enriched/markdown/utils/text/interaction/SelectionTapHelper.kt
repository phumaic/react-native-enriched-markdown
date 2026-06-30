package com.swmansion.enriched.markdown.utils.text.interaction

import android.view.MotionEvent
import android.widget.TextView

/**
 * Keeps an existing text selection — and its floating toolbar — alive when the
 * user taps inside it, instead of the editor clearing them on tap. Mirrors the
 * iOS tap-to-toggle behaviour where a tap on the selection no longer deselects
 * the text.
 *
 * When a press begins inside the current selection the whole gesture (down → up)
 * is consumed before the TextView's editor sees it, so the editor never tears
 * down the selection or dismisses its toolbar. Presses that start outside the
 * selection are not consumed and clear it as usual.
 */
class SelectionTapHelper(
  private val textView: TextView,
) {
  private var consuming = false

  /** Returns true if the event was consumed (a gesture that began inside the selection). */
  fun onTouchEvent(event: MotionEvent): Boolean {
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        consuming = isInsideSelection(event)
        return consuming
      }

      MotionEvent.ACTION_MOVE -> {
        if (consuming) return true
      }

      MotionEvent.ACTION_UP -> {
        if (consuming) {
          consuming = false
          return true
        }
      }

      MotionEvent.ACTION_CANCEL -> {
        if (consuming) {
          consuming = false
          return true
        }
      }
    }
    return false
  }

  private fun isInsideSelection(event: MotionEvent): Boolean {
    if (!textView.hasSelection()) return false
    val layout = textView.layout ?: return false
    val x = event.x.toInt() - textView.totalPaddingLeft + textView.scrollX
    val y = event.y.toInt() - textView.totalPaddingTop + textView.scrollY
    val line = layout.getLineForVertical(y)
    val offset = layout.getOffsetForHorizontal(line, x.toFloat())
    return offset >= textView.selectionStart && offset < textView.selectionEnd
  }
}
