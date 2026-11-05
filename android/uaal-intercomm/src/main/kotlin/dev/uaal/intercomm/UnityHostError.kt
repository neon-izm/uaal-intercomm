package dev.uaal.intercomm

sealed class UnityHostError(message: String) : Exception(message) {
    class MissingRuntime : UnityHostError("Unity のランタイムがアプリに入っていません")

    class TimedOut(val event: String) : UnityHostError("$event が時間内に返りませんでした")

    class Bridge(val op: String, message: String) : UnityHostError("$op: $message")

    class Unexpected(message: String) : UnityHostError(message)
}
