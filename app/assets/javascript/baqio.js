(function (E) {
    function handleSelectBaqioUrl() {
      const element = document.querySelector('#integration_parameters_baqio_web_address')
        
      if (element) {
        let new_element = document.createElement('select')
        new_element.innerHTML = '<option value="demo.baqio.com">demo.baqio.com</option>' + '<option value="app.baqio.com">app.baqio.com</option>'

        element.replaceWith(new_element);
      }
    }

    E.onDomReady(function () {
      handleSelectBaqioUrl() 
    })

})(ekylibre)