import "regenerator-runtime/runtime.js";

import { createApp, h } from 'vue';
import Upload from './Upload.vue';
import store from './Upload/store.js';
import Icon from './common/Icon';
import {httpGet} from "./common/util";

const app = createApp({
  data() {
    return {
      baseURI: document.head.getElementsByTagName('base')[0].href.replace(/\/$/),
      configFetched: false,
      lang: {},
    };
  },
  render: () => h(Upload),
  async created() {
    // Fetch translations
    try {
      this.lang = await httpGet('lang.json');
      this.$store.commit('LANG', this.lang);
    } catch (e) {
      alert(e);
    }

    // Fetch config
    try {
      await this.$store.dispatch('config/fetch');
    } catch(e) {
      if(e.code !== 'PWDREQ') {
        console.error(e);
      }
    }
    this.configFetched = true;
  }
});

app.component('icon', Icon);
app.use(store);
app.mount('#upload');

window.BURNBOX_VERSION = BURNBOX_VERSION;
