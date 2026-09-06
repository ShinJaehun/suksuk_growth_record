import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["gender", "option", "preview"]

  connect() {
    this.filterOptions()
  }

  changeGender() {
    this.filterOptions()

    const selected = this.selectedOption()
    if (selected && selected.dataset.gender === this.genderTarget.value) return

    const replacement = this.visibleOptions()[0]
    const input = replacement?.querySelector("input[type='radio']")
    if (!input) return

    input.checked = true
    this.updatePreview(input)
  }

  select(event) {
    this.updatePreview(event.currentTarget)
  }

  filterOptions() {
    const gender = this.genderTarget.value

    this.optionTargets.forEach((option) => {
      option.hidden = gender !== "" && option.dataset.gender !== gender
    })
  }

  selectedOption() {
    return this.optionTargets.find((option) => option.querySelector("input[type='radio']")?.checked)
  }

  visibleOptions() {
    return this.optionTargets.filter((option) => !option.hidden)
  }

  updatePreview(input) {
    if (!this.hasPreviewTarget) return

    this.previewTarget.src = input.dataset.avatarUrl
  }
}
