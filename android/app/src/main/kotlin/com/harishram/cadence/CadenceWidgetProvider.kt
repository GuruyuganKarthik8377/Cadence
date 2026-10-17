package com.harishram.cadence

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import android.content.SharedPreferences
import org.json.JSONArray

/**
 * Today's habits on the home screen.
 *
 * The widget is a pure renderer: Flutter writes the day's habits into shared
 * preferences via home_widget, and this reads them back. It never talks to
 * Supabase, so there is no auth or network code on the Android side.
 *
 * Rows are built statically rather than with a ListView/RemoteViewsService.
 * A collection adapter needs a bound Service and its own IPC, and the widget
 * only ever shows a handful of rows.
 */
class CadenceWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cadence_widget)

            val habitsJson = widgetData.getString("habits", "[]") ?: "[]"
            val doneCount = widgetData.getInt("done_count", 0)
            val totalCount = widgetData.getInt("total_count", 0)

            views.setTextViewText(
                R.id.widget_title,
                if (totalCount == 0) "No habits today" else "Today"
            )
            views.setTextViewText(
                R.id.widget_progress,
                if (totalCount == 0) "" else "$doneCount of $totalCount done"
            )

            // Tapping the header opens the app.
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )

            renderRows(context, views, habitsJson)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun renderRows(context: Context, views: RemoteViews, habitsJson: String) {
        val rowIds = listOf(R.id.widget_row_0, R.id.widget_row_1, R.id.widget_row_2)
        val nameIds = listOf(R.id.widget_name_0, R.id.widget_name_1, R.id.widget_name_2)
        val checkIds = listOf(R.id.widget_check_0, R.id.widget_check_1, R.id.widget_check_2)

        val habits = try {
            JSONArray(habitsJson)
        } catch (e: Exception) {
            JSONArray()
        }

        for (i in rowIds.indices) {
            if (i >= habits.length()) {
                views.setViewVisibility(rowIds[i], android.view.View.GONE)
                continue
            }
            val habit = habits.optJSONObject(i) ?: continue
            val id = habit.optString("id")
            val name = habit.optString("name")
            val done = habit.optBoolean("done")

            views.setViewVisibility(rowIds[i], android.view.View.VISIBLE)
            views.setTextViewText(nameIds[i], name)
            views.setImageViewResource(
                checkIds[i],
                if (done) R.drawable.widget_check_on else R.drawable.widget_check_off
            )

            // Deep link straight to the toggle; MainActivity hands the uri to
            // Flutter, which completes the habit and refreshes the widget.
            //
            // The action must be home_widget's own LAUNCH action, not
            // ACTION_VIEW: HomeWidgetPlugin gates both of its entry points
            // (initiallyLaunchedFromHomeWidget and the widgetClicked stream)
            // on that exact action and drops anything else, so an ACTION_VIEW
            // intent opened the app and then did nothing.
            //
            // The intent is explicit — it names MainActivity — so it needs no
            // intent-filter in the manifest and none is declared. An implicit
            // cadence://toggle filter would let any app, or any web page (via
            // BROWSABLE), tick off someone's habits.
            val intent = Intent(context, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = Uri.parse("cadence://toggle?habitId=$id")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            views.setOnClickPendingIntent(
                rowIds[i],
                PendingIntent.getActivity(
                    context,
                    id.hashCode(),
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }
    }
}
