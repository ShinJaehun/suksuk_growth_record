import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["school", "grade", "options", "classroom"]
  static values = { url: String, selectedId: Number }

  changeSchool() {
    this.selectedIdValue = 0
    this.gradeTarget.value = ""
    this.loadOptions()
  }

  changeGrade() {
    this.selectedIdValue = 0
    this.loadOptions()
  }

  async loadOptions() {
    const params = new URLSearchParams()
    if (this.schoolTarget.value !== "") params.set("school_id", this.schoolTarget.value)
    if (this.gradeTarget.value !== "") params.set("membership_grade", this.gradeTarget.value)
    if (this.selectedIdValue > 0) params.set("classroom_id", this.selectedIdValue)

    const response = await fetch(`${this.urlValue}?${params.toString()}`, {
      headers: { Accept: "text/html" }
    })
    if (!response.ok) return

    this.optionsTarget.innerHTML = await response.text()
  }
}
