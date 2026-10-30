import "regenerator-runtime/runtime.js";

if(!String.prototype.startsWith) {
  String.prototype.startsWith = function(searchString, position) {
    position = position || 0;
    return this.indexOf(searchString, position) === position;
  };
}

import { createApp, h } from 'vue';
import { httpGet } from "./common/util";
import Download from './Download.vue';
import Icon from './common/Icon';

const app = createApp({
  data() {
    return {
      baseURI: document.head.getElementsByTagName('base')[0].href.replace(/\/$/,''),
      lang: {},
    };
  },
  render: () => h(Download),
  async created() {
    // Fetch translations
    try {
      this.lang = await httpGet('lang.json');
    }
    catch (e) {
      alert(e);
    }
  }
});

app.component('icon', Icon);
app.mount('#download');

window.BURNBOX_VERSION = BURNBOX_VERSION;
