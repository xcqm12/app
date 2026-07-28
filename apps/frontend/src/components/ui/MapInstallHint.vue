<template>
  <Admonition v-if="hint" type="info" class="map-install-hint">
    <div class="font-semibold text-contrast">{{ hint.title }}</div>
    <ol class="mt-1 list-decimal pl-5 text-sm leading-6">
      <li v-for="(step, idx) in hint.steps" :key="idx" v-html="step" />
    </ol>
    <div v-if="hint.note" class="mt-2 text-xs text-secondary">{{ hint.note }}</div>
  </Admonition>
</template>

<script lang="ts" setup>
import { Admonition } from "@modrinth/ui";
import { computed } from "vue";

const props = defineProps<{
  filename?: string | null;
  categories?: string[] | null;
}>();

interface Hint {
  title: string;
  steps: string[];
  note?: string;
}

const LITEMATIC: Hint = {
  title: "用 Litematica 投影模组加载",
  steps: [
    "安装 <strong>Litematica</strong> 模组（依赖 Fabric Loader + Fabric API，或 Forge 移植版）",
    "将 <code>.litematic</code> 文件放入 <code>.minecraft/schematics/</code>",
    "进入游戏按 <strong>M</strong> 键打开 Litematica 菜单 → <strong>Load schematic</strong>",
    "选中文件 → <strong>Load</strong>，再用 <strong>Place schematic</strong> 投影到世界",
  ],
  note: "Litematica 仅做投影显示，需配合 Printer / WorldEdit 才能真正生成方块。",
};

const SCHEM: Hint = {
  title: "用 WorldEdit 加载示意图（schematic）",
  steps: [
    "服务端：放入 <code>plugins/WorldEdit/schematics/</code>",
    "单机模组版：放入 <code>config/worldedit/schematics/</code>",
    "进入游戏输入 <code>//schem load &lt;文件名&gt;</code>",
    "站到目标位置输入 <code>//paste</code> 粘贴",
  ],
  note: ".schem 是 1.13+ 的 Sponge 格式，.schematic 是旧版 MCEdit 格式，二者命令一致。",
};

const NBT_STRUCTURE: Hint = {
  title: "用结构方块加载（NBT）",
  steps: [
    "放入存档目录 <code>&lt;存档名&gt;/generated/&lt;命名空间&gt;/structures/</code>（默认命名空间为 <code>minecraft</code>）",
    "进入游戏放置一个 <strong>结构方块</strong>，模式选 <strong>加载</strong>",
    "输入结构名 <code>命名空间:文件名</code>（不含后缀）",
    "点击 <strong>加载</strong> 显示边框 → 再点 <strong>加载</strong> 生成方块",
  ],
  note: "需要创造模式权限或开启 OP 才能放置结构方块。",
};

const BEDROCK_STRUCTURE: Hint = {
  title: "导入到基岩版（mcstructure）",
  steps: [
    "将 <code>.mcstructure</code> 文件放入对应行为包的 <code>structures/</code> 目录",
    "在游戏中通过命令 <code>/structure load</code> 加载",
  ],
};

const BEDROCK_WORLD: Hint = {
  title: "导入到基岩版存档",
  steps: [
    "在 PC / 手机 / 平板上 <strong>双击文件</strong>，系统会调用基岩版自动导入",
    "若未生效：将文件改名为 <code>.zip</code>，解压到 <code>games/com.mojang/minecraftWorlds/</code>",
  ],
};

const JAVA_WORLD: Hint = {
  title: "导入到单人地图",
  steps: [
    "解压压缩包，得到一个含 <code>level.dat</code> 的存档文件夹",
    "把整个文件夹放进 <code>.minecraft/saves/</code>",
    "启动 Minecraft → <strong>单人游戏</strong> 中即可看到该地图",
  ],
  note: "若加入服务器使用，请放入服务端工作目录的 <code>world/</code>（按服务端配置可能为其他名称）。",
};

const SCHEM_BUNDLE: Hint = {
  title: "压缩包内为建筑模板",
  steps: [
    "解压压缩包",
    "根据内含文件类型按相应方式加载（<code>.litematic</code> / <code>.schem</code> / <code>.nbt</code> 等）",
  ],
};

const STRUCTURE_BUNDLE: Hint = {
  title: "压缩包内为结构文件",
  steps: [
    "解压压缩包",
    "将 <code>.nbt</code> 文件放入存档的 <code>generated/&lt;命名空间&gt;/structures/</code>",
    "用结构方块加载（同结构文件加载流程）",
  ],
};

const hint = computed<Hint | null>(() => {
  const name = (props.filename || "").toLowerCase().trim();
  const cats = props.categories || [];

  if (name.endsWith(".litematic")) return LITEMATIC;
  if (name.endsWith(".schem") || name.endsWith(".schematic")) return SCHEM;
  if (name.endsWith(".nbt")) return NBT_STRUCTURE;
  if (name.endsWith(".mcstructure")) return BEDROCK_STRUCTURE;
  if (name.endsWith(".mcworld") || name.endsWith(".mctemplate")) return BEDROCK_WORLD;

  if (name.endsWith(".zip")) {
    if (cats.includes("完整地图")) return JAVA_WORLD;
    if (cats.includes("建筑模板")) return SCHEM_BUNDLE;
    if (cats.includes("结构文件")) return STRUCTURE_BUNDLE;
    return JAVA_WORLD;
  }

  return null;
});
</script>

<style scoped>
.map-install-hint :deep(code) {
  padding: 0.05em 0.3em;
  background: var(--color-button-bg);
  border-radius: 4px;
  font-size: 0.85em;
}
</style>
