package com.eduard.nutribalance

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Виджет «Моя Ева»: день цикла и калории на сегодня. Данные пишет HomeWidgetService во Flutter. */
class EvaWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.eva_widget).apply {
                setTextViewText(R.id.widget_day, widgetData.getString("cycle_day", "—"))
                setTextViewText(R.id.widget_phase, widgetData.getString("cycle_phase", "Открой приложение"))
                setTextViewText(R.id.widget_kcal, widgetData.getString("kcal_left", "—"))
                setTextViewText(R.id.widget_kcal_label, widgetData.getString("kcal_label", "ккал осталось"))
                val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, launch)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
