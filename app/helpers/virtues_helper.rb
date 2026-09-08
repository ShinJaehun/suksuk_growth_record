module VirtuesHelper
  def virtue_color_options(virtue, active_virtues:)
    used_color_keys = active_virtues.reject { |item| item.id == virtue.id }.map(&:color_key)

    Virtue::COLORS.keys
      .reject { |key| used_color_keys.include?(key) }
      .map { |key| [t("virtues.colors.#{key}"), key] }
  end

  def virtue_color_swatch(virtue)
    color = Virtue::COLORS[virtue.color_key]
    return unless color

    tag.span class: "inline-block h-4 w-4 shrink-0 rounded-full",
      style: "background-color: #{color}",
      aria: { label: t("virtues.colors.#{virtue.color_key}") }
  end
end
