function webkit_send(req, onsuc, onerr) {
    window.webkit.messageHandlers.bridge.postMessage(req).then(res => {
        if (onsuc) {
            onsuc(res);
        }
    }).catch(err => {
        if (onerr) {
            onerr(err);
        } else {
            console.log("webkit_send unhandled err " + err);
        }
    });
}

const App = {
    el: '#app',
    data: function () {
        return {
            title: "Daeman",
            loading: false,
            show_sys: false,
            known_daemon: {},
            daemon_list: [
                {"Label": "label1", "Pid": 1, "Status": 0, "Type": 8},
                {"Label": "label2", "Pid": 2, "Status": 0, "Type": 8},
                {"Label": "label3", "Pid": 3, "Status": 0, "Type": 8}
            ],
            show_detail: {},
        }
    },
    methods: {
        get_desc: function(item, type) {
            if (type == "label") {
                var name = item.Label;
                return name.replace("com.apple.", "");
            }
            if (type == "simple") {
                var name = item.Label;
                if (this.known_daemon[name]) {
                    name = this.known_daemon[name]["simple"][0];
                }
                return name + " Status:" + (item.Pid>=0?"Running":"Stopped");
            }
            var name = item.Label;
            if (this.known_daemon[name]) {
                name = this.known_daemon[name]["detail"][0];
            }
            return name;
        },
        click_ctrl: function(item) {
            var that = this;
            webkit_send({
                api: "ctrl_daemon",
                label: item["Label"],
                plist: item["Plist"],
                start: item.Pid>=0?"0":"1",
                flag: 0,
            }, data => {
                if (data == -1) {
                    alert("load/unload failed");
                } else if (data == -2) {
                    alert("start/stop failed");
                } else {
                    that.update_daemon();
                }
            });
        },
        click_show: function(item) {
            this.$set(this.show_detail, item.Label, !this.show_detail[item.Label]);
        },
        update_icon: function(item) {
            return 'el-icon-arrow-'+(this.show_detail[item.Label]?'down':'right');
        },
        block_ui: function(flag) {
            this.loading = flag;
        },
        update_daemon: function() {
            var that = this;
            that.block_ui(true);
            webkit_send({api: "list_daemon"}, data => {
                that.daemon_list = data;
                setTimeout(() => {
                    that.block_ui(false);
                }, 500);
            });
        },
        init_global: function() {
            var that = this;
            webkit_send({api: "init"}, data => {
                that.known_daemon = data;
            }, err => {
                console.log("bridge not work");
            });
            setInterval(() => {
                that.update_daemon();
            }, 10000);
            that.update_daemon();
        }
    },
    mounted: function () {
        this.init_global();
    }
};

window.addEventListener('load', function () {
    window.app = new Vue(App);
})

