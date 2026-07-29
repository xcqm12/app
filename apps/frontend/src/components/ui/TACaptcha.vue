<script>
export default {
  props: {
    modelValue: {
      type: String,
      required: true,
    },
    type: {
      type: String,
      default: "SLIDER",
    },
    requestUrl: {
      type: String,
      default: "https://captcha.bbsmc.org.cn/gen",
    },
    validUrl: {
      type: String,
      default: "https://captcha.bbsmc.org.cn/validation",
    },
    sdkUrl: {
      type: String,
      default: "https://captcha.bbsmc.org.cn/sdk/tac",
    },
    logoUrl: {
      type: String,
      default:
        "https://cdn.bbsmc.org.cn/bbsmc/data/ZcUCcMEr/317f155094c061b70526b21f83619037a4a962e7.png",
    },
    showOverlay: {
      type: Boolean,
      default: false,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      internalToken: this.modelValue,
      tacInstance: null,
      isLoaded: false,
      isVerifying: false,
      loadFailed: false,
    };
  },
  mounted() {
    if (this.disabled) {
      this.onTokenUpdate("captcha-disabled");
      return;
    }
    this.loadTACScript();
  },
  beforeUnmount() {
    if (this.tacInstance) {
      this.tacInstance.destroyWindow();
    }
  },
  watch: {
    modelValue(newValue) {
      this.internalToken = newValue;
    },
    type() {
      if (this.isVerifying) {
        this.initCaptcha();
      }
    },
  },
  methods: {
    async loadTACScript() {
      try {
        await this.loadScript(`${this.sdkUrl}/load.js`);
        this.isLoaded = true;
      } catch (error) {
        this.loadFailed = true;
        this.isLoaded = false;
        this.onTokenUpdate("captcha-unavailable");
      }
    },

    loadScript(src) {
      return new Promise((resolve, reject) => {
        if (document.querySelector(`script[src="${src}"]`)) {
          resolve();
          return;
        }

        const script = document.createElement("script");
        script.src = src;
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });
    },

    async initCaptcha() {
      if (!this.isLoaded || !window.initTAC) {
        return;
      }

      if (this.tacInstance) {
        this.tacInstance.destroyWindow();
      }

      this.isVerifying = true;

      // 预检: 验证验证码服务是否可用
      try {
        const testResponse = await fetch(`${this.requestUrl}?type=${this.type}`, {
          method: "GET",
          signal: AbortSignal.timeout(5000),
        });
        if (!testResponse.ok) {
          throw new Error(`Captcha service returned ${testResponse.status}`);
        }
      } catch (error) {
        this.isVerifying = false;
        this.loadFailed = true;
        this.onTokenUpdate("captcha-unavailable");
        return;
      }

      const captchaConfig = {
        requestCaptchaDataUrl: `${this.requestUrl}?type=${this.type}`,
        validCaptchaUrl: this.validUrl,
        bindEl: "#captcha-box",
        timeToTimestamp: false,
        validSuccess: (res, c, t) => {
          t.destroyWindow();
          this.isVerifying = false;
          this.onTokenUpdate(res.data.token);
        },
        validFail: (res, c, t) => {
          t.reloadCaptcha();
        },
        btnRefreshFun: (el, tac) => {
          tac.reloadCaptcha();
        },
        btnCloseFun: (el, tac) => {
          tac.destroyWindow();
          this.isVerifying = false;
        },
      };

      const style = {
        logoUrl: this.logoUrl,
      };

      try {
        const tac = await window.initTAC(this.sdkUrl, captchaConfig, style);

        tac.config.insertRequestChain(0, {
          preRequest(type, requestParam) {
            return true;
          },
          postRequest(type, requestParam, res) {
            return true;
          },
        });

        this.tacInstance = tac;
        tac.init();
      } catch (error) {
        this.isVerifying = false;
        this.loadFailed = true;
        this.onTokenUpdate("captcha-unavailable");
      }
    },

    onTokenUpdate(token) {
      this.internalToken = token;
      this.$emit("update:modelValue", token);
    },

    showCaptcha() {
      if (this.disabled || this.loadFailed) {
        this.onTokenUpdate("captcha-unavailable");
        return;
      }
      if (!this.isLoaded) {
        return;
      }
      this.initCaptcha();
    },

    reloadCaptcha() {
      if (this.tacInstance) {
        this.tacInstance.reloadCaptcha();
      }
    },

    destroyCaptcha() {
      if (this.tacInstance) {
        this.tacInstance.destroyWindow();
        this.isVerifying = false;
      }
    },

    resetCaptcha() {
      this.destroyCaptcha();
      this.tacInstance = null;
      this.isVerifying = false;
      this.onTokenUpdate("");
    },
  },
};
</script>

<template>
  <div class="tac-captcha-container">
    <div v-if="isVerifying && showOverlay" class="captcha-overlay" @click="destroyCaptcha"></div>

    <div class="main-captcha-button">
      <button
        v-if="disabled || loadFailed"
        class="captcha-btn captcha-btn-success"
        type="button"
        disabled
      >
        <span class="btn-text">验证通过</span>
        <span class="btn-icon">✓</span>
      </button>

      <button
        v-else-if="!internalToken && !isVerifying"
        @click="showCaptcha"
        class="captcha-btn captcha-btn-start"
        type="button"
      >
        <span class="btn-text">点击按钮开始验证</span>
      </button>

      <button
        v-else-if="!internalToken && isVerifying"
        class="captcha-btn captcha-btn-verifying"
        type="button"
        disabled
      >
        <span class="btn-text">验证中...</span>
      </button>

      <button v-else class="captcha-btn captcha-btn-success" type="button" disabled>
        <span class="btn-text">验证通过</span>
        <span class="btn-icon">✓</span>
      </button>
    </div>

    <div id="captcha-box" class="captcha-box-container" v-show="isVerifying"></div>

    <div v-if="$attrs.showDebugControls" class="captcha-controls">
      <button
        @click="reloadCaptcha"
        class="btn btn-secondary"
        type="button"
        :disabled="!tacInstance"
      >
        刷新验证码
      </button>

      <button @click="destroyCaptcha" class="btn btn-danger" type="button" :disabled="!tacInstance">
        关闭验证码
      </button>

      <button @click="resetCaptcha" class="btn btn-warning" type="button">重置状态</button>
    </div>
  </div>
</template>

<style scoped>
.tac-captcha-container {
  width: 100%;
  position: relative;
}

/* 主要验证按钮样式 */
.main-captcha-button {
  margin: 15px 0;
  display: flex;
  justify-content: center;
}

.captcha-btn {
  width: 60%;
  height: 50px;
  border: 2px solid;
  border-radius: 6px;
  background: white;
  cursor: pointer;
  font-size: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0 15px;
  transition: all 0.3s ease;
  position: relative;
  border-left: 4px solid transparent;
}

/* 点击开始验证按钮 - 灰色状态 */
.captcha-btn-start {
  border-color: #d1d5db;
  color: #6b7280;
  background-color: #f9fafb;
}

.captcha-btn-start:hover {
  background-color: #f3f4f6;
  border-color: #9ca3af;
  border-left-color: #3b82f6;
  color: #374151;
}

.captcha-btn-start:active {
  background-color: #e5e7eb;
}

/* 验证中状态按钮 - 蓝色 */
.captcha-btn-verifying {
  border-color: #3b82f6;
  color: #3b82f6;
  cursor: not-allowed;
  border-left-color: #3b82f6;
  background-color: #eff6ff;
}

/* 验证成功按钮 - 绿色 */
.captcha-btn-success {
  border-color: #10b981;
  color: #10b981;
  background-color: #ecfdf5;
  cursor: not-allowed;
  border-left-color: #10b981;
}

.btn-text {
  flex: 1;
  text-align: center;
  font-weight: 500;
}

.btn-icon {
  font-size: 18px;
  margin-left: 10px;
}

.captcha-box {
  margin: 10px 0;
  min-height: 200px;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* 验证码容器 - 弹窗样式 */
.captcha-box-container {
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  z-index: 10001;
  background-color: transparent;
  border-radius: 8px;
  max-width: 90vw;
  max-height: 90vh;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* 验证码内容样式 */
.captcha-box-container > * {
  margin: 0 auto;
  display: block;
}

/* 可选遮罩层 */
.captcha-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(0, 0, 0, 0.5);
  z-index: 10000;
  cursor: pointer;
}

/* 调试控制按钮 */
.captcha-controls {
  display: flex;
  gap: 10px;
  margin-top: 10px;
  padding: 10px;
  background-color: #f5f5f5;
  border-radius: 4px;
  border-left: 3px solid #ffc107;
}

.captcha-controls::before {
  content: "🛠️ 调试控制: ";
  font-size: 12px;
  color: #666;
  align-self: center;
  margin-right: 5px;
}

.btn {
  padding: 6px 12px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 12px;
  transition: background-color 0.3s;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn-secondary {
  background-color: #6c757d;
  color: white;
}

.btn-secondary:hover:not(:disabled) {
  background-color: #545b62;
}

.btn-danger {
  background-color: #dc3545;
  color: white;
}

.btn-danger:hover:not(:disabled) {
  background-color: #c82333;
}

.btn-warning {
  background-color: #ffc107;
  color: #212529;
}

.btn-warning:hover:not(:disabled) {
  background-color: #e0a800;
}

/* TAC验证码弹窗样式调整 */
:deep(.tac-modal) {
  z-index: 9999 !important;
}

/* 响应式设计 */
@media (max-width: 480px) {
  .captcha-btn {
    height: 45px;
    font-size: 13px;
    padding: 0 12px;
  }

  .btn-icon {
    font-size: 16px;
  }

  .captcha-controls {
    flex-direction: column;
  }
}
</style>
