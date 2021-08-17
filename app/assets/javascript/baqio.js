(function (E) {
    function handleSelectBaqioUrl() {        
      if (document.querySelector("#integration_nature[value='baqio']") != undefined) {
        const element = document.querySelector('#integration_parameters_url')
        let new_element = document.createElement('select')
        new_element.setAttribute("id", "integration_parameters_url")
        new_element.setAttribute("name", "integration[parameters][url]")
        new_element.innerHTML = '<option value="demo.baqio.com">demo.baqio.com</option>' + '<option value="app.baqio.com">app.baqio.com</option>'

        element.replaceWith(new_element);
      }
    }

    E.onDomReady(function () {
      handleSelectBaqioUrl() 
    })

})(ekylibre)