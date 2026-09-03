module SchoolsHelper
  SCHOOL_COLOR_SWATCH_CLASSES = {
    "sky" => "bg-sky-500",
    "emerald" => "bg-emerald-500",
    "violet" => "bg-violet-500",
    "amber" => "bg-amber-500",
    "rose" => "bg-rose-500",
    "teal" => "bg-teal-500",
    "indigo" => "bg-indigo-500",
    "orange" => "bg-orange-500"
  }.freeze

  SCHOOL_COLOR_CARD_CLASSES = {
    "sky" => "border-sky-200 bg-sky-50/70",
    "emerald" => "border-emerald-200 bg-emerald-50/70",
    "violet" => "border-violet-200 bg-violet-50/70",
    "amber" => "border-amber-200 bg-amber-50/70",
    "rose" => "border-rose-200 bg-rose-50/70",
    "teal" => "border-teal-200 bg-teal-50/70",
    "indigo" => "border-indigo-200 bg-indigo-50/70",
    "orange" => "border-orange-200 bg-orange-50/70"
  }.freeze

  SCHOOL_COLOR_ROW_CLASSES = {
    "sky" => "border-l-4 border-l-sky-400 bg-sky-50/60",
    "emerald" => "border-l-4 border-l-emerald-400 bg-emerald-50/60",
    "violet" => "border-l-4 border-l-violet-400 bg-violet-50/60",
    "amber" => "border-l-4 border-l-amber-400 bg-amber-50/60",
    "rose" => "border-l-4 border-l-rose-400 bg-rose-50/60",
    "teal" => "border-l-4 border-l-teal-400 bg-teal-50/60",
    "indigo" => "border-l-4 border-l-indigo-400 bg-indigo-50/60",
    "orange" => "border-l-4 border-l-orange-400 bg-orange-50/60"
  }.freeze

  def school_color_swatch_class(color_key)
    SCHOOL_COLOR_SWATCH_CLASSES.fetch(color_key, "bg-slate-400")
  end

  def school_color_card_class(color_key)
    SCHOOL_COLOR_CARD_CLASSES.fetch(color_key, "border-slate-200 bg-white")
  end

  def school_color_row_class(color_key)
    SCHOOL_COLOR_ROW_CLASSES.fetch(color_key, "border-l-4 border-l-slate-200 bg-white")
  end

end
