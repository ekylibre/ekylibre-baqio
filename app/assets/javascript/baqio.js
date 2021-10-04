(function (E) {
    function handleSelectBaqioUrl() {        
      if (document.querySelector("#integration_nature[value='baqio']") != undefined) {
        const element = document.querySelector('#integration_parameters_url')
        let new_element = document.createElement('select')
        new_element.setAttribute("id", "integration_parameters_url")
        new_element.setAttribute("name", "integration[parameters][url]")
        new_element.innerHTML = '<option value="app.baqio.com">app.baqio.com</option>' + '<option value="demo.baqio.com">demo.baqio.com</option>'

        element.replaceWith(new_element);
      }
    }

    function disabledBaqioIntegrationButton() {
      const element = document.querySelector('.notification_body')

      if (element.innerText.includes('Baqio')) {
        const formActions = document.querySelector(".form-actions")
        formActions.querySelector("input").disabled = true
      }
    }

    E.onDomReady(function () {
      handleSelectBaqioUrl()
      disabledBaqioIntegrationButton()
    })

})(ekylibre)